import Foundation

/// Minimal reader for Garmin FIT activity files (as recorded by MyWhoosh, Zwift, Wahoo …).
/// Reads only what a ride summary needs: the `session` message and, as a fallback, the per-second `record`s.
public enum FITParser {
    public enum Error: Swift.Error, Equatable { case notFIT, truncated, noData }

    /// Seconds between the Unix epoch and the FIT epoch (1989-12-31 00:00 UTC).
    static let fitEpoch: TimeInterval = 631_065_600

    public struct Summary: Equatable, Sendable {
        public var startDate: Date
        public var movingTime: Int
        public var distance: Double
        public var averageWatts: Double?
        public var normalizedPower: Double?
        public var kilojoules: Double?
        public var averageHeartrate: Double?
        public var maxHeartrate: Double?
        /// Highest 1 Hz power sample (after capping absurd values).
        public var maxWatts: Double? = nil
        /// Mean-maximal power per standard duration from the 1 Hz series; nil without power data.
        public var powerCurve: [Int: Double]? = nil
        /// Pw:HR decoupling in percent (first vs second half, positive = pulse drifts up); nil without 1 Hz power and
        /// heart rate or for rides under 20 min.
        public var decoupling: Double? = nil
        /// Fatigue resistance in percent (see `Durability`); nil for rides under 60 min or without power.
        public var durability: Double? = nil
    }

    /// Power samples above this are sensor glitches and count as 0 W.
    static let maxPlausibleWatts: UInt64 = 2500

    public static func summary(from data: Data) throws -> Summary {
        let messages = try decode(data)
        let sessions = messages.filter { $0.global == 18 }
        let records = messages.filter { $0.global == 20 }
        let fromRecords = recordSummary(records)
        let series = powerSeries(records)
        let curve = series.map(PowerCurve.meanMaximal(watts:)).flatMap { $0.isEmpty ? nil : $0 }
        let maxWatts = series?.max()
        let decoupling = series.flatMap { power in
            AerobicEfficiency.decoupling(power: power, heartRate: heartRateSeries(records, count: power.count, origin: powerOrigin(records)))
        }

        let durability = series.flatMap(Durability.percent(power:))

        if let s = sessions.first, let start = s.uint(2).map(date) ?? fromRecords?.startDate {
            let timer = (s.uint(8) ?? s.uint(7)).map { Int(Double($0) / 1000) } ?? fromRecords?.movingTime ?? 0
            let work = s.uint(48).map { Double($0) / 1000 }
            return Summary(startDate: start,
                           movingTime: timer,
                           distance: s.uint(9).map { Double($0) / 100 } ?? fromRecords?.distance ?? 0,
                           averageWatts: s.uint(20).map { Double($0) } ?? fromRecords?.averageWatts,
                           normalizedPower: s.uint(34).map { Double($0) } ?? fromRecords?.normalizedPower,
                           kilojoules: work ?? fromRecords?.kilojoules,
                           averageHeartrate: s.uint(16).map { Double($0) } ?? fromRecords?.averageHeartrate,
                           maxHeartrate: s.uint(17).map { Double($0) } ?? fromRecords?.maxHeartrate,
                           maxWatts: maxWatts, powerCurve: curve, decoupling: decoupling, durability: durability)
        }
        guard var fromRecords else { throw Error.noData }
        fromRecords.maxWatts = maxWatts
        fromRecords.powerCurve = curve
        fromRecords.decoupling = decoupling
        fromRecords.durability = durability
        return fromRecords
    }

    /// Per-second power of the whole file (index 0 = first record), for tests and callers that need the series.
    public static func powerSeries(from data: Data) -> [Double]? {
        powerSeries(((try? decode(data)) ?? []).filter { $0.global == 20 })
    }

    /// Per-second heart rate aligned with `powerSeries(from:)` (same origin and length); 0 = no sample in that second.
    public static func heartRateSeries(from data: Data) -> [Double]? {
        let records = ((try? decode(data)) ?? []).filter { $0.global == 20 }
        guard let power = powerSeries(records) else { return nil }
        return heartRateSeries(records, count: power.count, origin: powerOrigin(records))
    }

    /// Timestamp of the first record that carries power (index 0 of `powerSeries`).
    static func powerOrigin(_ records: [Message]) -> UInt64? {
        records.compactMap { r in r.uint(7) != nil ? r.uint(253) : nil }.min()
    }

    /// Resamples the `record` heart rate (field 3) to 1 Hz on the power time axis: later record in the same second wins,
    /// seconds without a sample stay 0 (callers ignore them), 0 bpm readings stay 0.
    static func heartRateSeries(_ records: [Message], count: Int, origin: UInt64?) -> [Double] {
        var series = [Double](repeating: 0, count: count)
        guard let origin else { return series }
        for r in records {
            guard let t = r.uint(253), let hr = r.uint(3), t >= origin, Int(t - origin) < count else { continue }
            series[Int(t - origin)] = Double(hr)
        }
        return series
    }

    /// Resamples the `record` power values to 1 Hz by timestamp: gaps are filled with 0 W, values above
    /// `maxPlausibleWatts` become 0 W, a later record in the same second wins. nil when no record carries power.
    static func powerSeries(_ records: [Message]) -> [Double]? {
        let samples = records.compactMap { r -> (t: UInt64, p: UInt64)? in
            guard let t = r.uint(253), let p = r.uint(7) else { return nil }
            return (t, p)
        }
        guard let first = samples.map(\.t).min(), let last = samples.map(\.t).max() else { return nil }
        var series = [Double](repeating: 0, count: Int(last - first) + 1)
        for s in samples { series[Int(s.t - first)] = s.p > maxPlausibleWatts ? 0 : Double(s.p) }
        return series
    }

    // MARK: Records fallback

    static func recordSummary(_ records: [Message]) -> Summary? {
        let samples = records.compactMap { r -> (t: UInt64, power: UInt64?, hr: UInt64?, dist: UInt64?)? in
            guard let t = r.uint(253) else { return nil }
            return (t, r.uint(7), r.uint(3), r.uint(5))
        }
        guard let first = samples.first, let last = samples.last, last.t > first.t else { return nil }
        let powers = samples.compactMap(\.power).map { Double($0) }
        let hrs = samples.compactMap(\.hr).map { Double($0) }
        let avgPower = powers.isEmpty ? nil : powers.reduce(0, +) / Double(powers.count)
        return Summary(startDate: date(first.t),
                       movingTime: Int(last.t - first.t),
                       distance: samples.last(where: { $0.dist != nil })?.dist.map { Double($0) / 100 } ?? 0,
                       averageWatts: avgPower,
                       normalizedPower: normalizedPower(powers),
                       kilojoules: avgPower.map { $0 * Double(last.t - first.t) / 1000 },
                       averageHeartrate: hrs.isEmpty ? nil : hrs.reduce(0, +) / Double(hrs.count),
                       maxHeartrate: hrs.max())
    }

    /// Coggan NP from 1 Hz samples: 30 s rolling mean, 4th power, mean, 4th root.
    static func normalizedPower(_ watts: [Double]) -> Double? {
        guard watts.count >= 30 else { return nil }
        var rolling: [Double] = []
        var sum = watts[0..<30].reduce(0, +)
        rolling.append(sum / 30)
        for i in 30..<watts.count {
            sum += watts[i] - watts[i - 30]
            rolling.append(sum / 30)
        }
        let mean4 = rolling.reduce(0) { $0 + pow($1, 4) } / Double(rolling.count)
        return pow(mean4, 0.25)
    }

    static func date(_ fitSeconds: UInt64) -> Date { Date(timeIntervalSince1970: fitEpoch + TimeInterval(fitSeconds)) }

    // MARK: Decoder

    struct Message {
        var global: UInt16
        var fields: [UInt8: UInt64]
        /// `nil` for FIT's "invalid" sentinel (all bits set for the field's size).
        func uint(_ number: UInt8) -> UInt64? { fields[number] }
    }

    private struct Definition {
        var global: UInt16
        var bigEndian: Bool
        var fields: [(number: UInt8, size: Int)]
        var developerBytes: Int
    }

    static func decode(_ data: Data) throws -> [Message] {
        let bytes = [UInt8](data)
        guard bytes.count >= 12 else { throw Error.notFIT }
        let headerSize = Int(bytes[0])
        guard headerSize >= 12, bytes.count >= headerSize, bytes[8...11] == [0x2E, 0x46, 0x49, 0x54] else { throw Error.notFIT }
        let dataSize = Int(bytes[4]) | Int(bytes[5]) << 8 | Int(bytes[6]) << 16 | Int(bytes[7]) << 24
        let end = min(headerSize + dataSize, bytes.count)

        var definitions: [UInt8: Definition] = [:]
        var messages: [Message] = []
        var lastTimestamp: UInt64?
        var i = headerSize
        while i < end {
            let header = bytes[i]; i += 1
            if header & 0x80 != 0 {                         // compressed timestamp header → data message
                guard let def = definitions[(header >> 5) & 0x03] else { throw Error.truncated }
                var message = try readData(def, bytes, &i, end)
                if let last = lastTimestamp {
                    let offset = UInt64(header & 0x1F)
                    var ts = (last & ~0x1F) + offset
                    if offset < last & 0x1F { ts += 0x20 }
                    message.fields[253] = ts
                    lastTimestamp = ts
                }
                messages.append(message)
            } else if header & 0x40 != 0 {               // definition message
                guard i + 5 <= end else { throw Error.truncated }
                let big = bytes[i + 1] == 1
                let global = big ? UInt16(bytes[i + 2]) << 8 | UInt16(bytes[i + 3]) : UInt16(bytes[i + 3]) << 8 | UInt16(bytes[i + 2])
                let count = Int(bytes[i + 4]); i += 5
                guard i + count * 3 <= end else { throw Error.truncated }
                var fields: [(UInt8, Int)] = []
                for f in 0..<count { fields.append((bytes[i + f * 3], Int(bytes[i + f * 3 + 1]))) }
                i += count * 3
                var devBytes = 0
                if header & 0x20 != 0 {                     // developer fields: only skipped
                    guard i < end else { throw Error.truncated }
                    let devCount = Int(bytes[i]); i += 1
                    guard i + devCount * 3 <= end else { throw Error.truncated }
                    for f in 0..<devCount { devBytes += Int(bytes[i + f * 3 + 1]) }
                    i += devCount * 3
                }
                definitions[header & 0x0F] = Definition(global: global, bigEndian: big, fields: fields, developerBytes: devBytes)
            } else {
                guard let def = definitions[header & 0x0F] else { throw Error.truncated }
                let message = try readData(def, bytes, &i, end)
                if let ts = message.uint(253) { lastTimestamp = ts }
                messages.append(message)
            }
        }
        return messages
    }

    private static func readData(_ def: Definition, _ bytes: [UInt8], _ i: inout Int, _ end: Int) throws -> Message {
        var fields: [UInt8: UInt64] = [:]
        for field in def.fields {
            guard i + field.size <= end else { throw Error.truncated }
            // Only scalar unsigned fields up to 8 bytes are needed; arrays/strings are skipped.
            if [1, 2, 4].contains(field.size) {
                var value: UInt64 = 0
                for b in 0..<field.size {
                    let byte = UInt64(bytes[i + (def.bigEndian ? b : field.size - 1 - b)])
                    value = value << 8 | byte
                }
                let invalid: UInt64 = field.size == 1 ? 0xFF : field.size == 2 ? 0xFFFF : 0xFFFF_FFFF
                if value != invalid { fields[field.number] = value }
            }
            i += field.size
        }
        guard i + def.developerBytes <= end else { throw Error.truncated }
        i += def.developerBytes
        return Message(global: def.global, fields: fields)
    }
}
