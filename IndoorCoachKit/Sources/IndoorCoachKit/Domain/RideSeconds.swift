import Foundation

/// The 1 Hz data of a ride (power, optionally heart rate), kept after a FIT import so later analyses (time in zones,
/// planned vs. actual per interval) can use it. Compact binary: 1 h ≈ 11 KB.
///
/// Format v1: version (1 byte), flags (bit 0 = heart rate present), count (UInt32 LE), power (count × UInt16 LE),
/// heart rate (count × UInt8) when present.
public struct RideSeconds: Equatable, Sendable {
    public static let formatVersion: UInt8 = 1

    /// Watts per second (index 0 = first second with power); gaps are 0.
    public var power: [UInt16]
    /// Beats per minute aligned with `power`; 0 = no sample. nil when the file has no heart rate.
    public var heartRate: [UInt8]?

    public init(power: [UInt16], heartRate: [UInt8]?) {
        self.power = power
        self.heartRate = heartRate.flatMap { $0.count == power.count ? $0 : nil }
    }

    /// From the parser's Double series (clamped to the storage range).
    public init(watts: [Double], beatsPerMinute: [Double]?) {
        func clamp<T: FixedWidthInteger>(_ v: Double, _: T.Type) -> T {
            guard v.isFinite, v > 0 else { return 0 }
            return v >= Double(T.max) ? T.max : T(v.rounded())
        }
        let hr = beatsPerMinute.map { $0.map { clamp($0, UInt8.self) } }
        self.init(power: watts.map { clamp($0, UInt16.self) }, heartRate: hr?.contains { $0 > 0 } == true ? hr : nil)
    }

    public var count: Int { power.count }
    public var watts: [Double] { power.map(Double.init) }
    public var beatsPerMinute: [Double]? { heartRate.map { $0.map(Double.init) } }

    public func encoded() -> Data {
        var data = Data(capacity: 6 + power.count * 3)
        data.append(Self.formatVersion)
        data.append(heartRate == nil ? 0 : 1)
        withUnsafeBytes(of: UInt32(power.count).littleEndian) { data.append(contentsOf: $0) }
        for p in power { withUnsafeBytes(of: p.littleEndian) { data.append(contentsOf: $0) } }
        if let heartRate { data.append(contentsOf: heartRate) }
        return data
    }

    public static func decode(_ data: Data?) -> RideSeconds? {
        guard let data, data.count >= 6 else { return nil }
        let bytes = [UInt8](data)
        guard bytes[0] == formatVersion else { return nil }
        let hasHR = bytes[1] & 1 == 1
        let count = Int(bytes[2]) | Int(bytes[3]) << 8 | Int(bytes[4]) << 16 | Int(bytes[5]) << 24
        guard count > 0, count <= FITParser.maxSeriesSeconds, bytes.count == 6 + count * 2 + (hasHR ? count : 0) else { return nil }
        var power = [UInt16](repeating: 0, count: count)
        for i in 0..<count { power[i] = UInt16(bytes[6 + 2 * i]) | UInt16(bytes[7 + 2 * i]) << 8 }
        let hr = hasHR ? Array(bytes[(6 + 2 * count)...]) : nil
        return RideSeconds(power: power, heartRate: hr)
    }
}
