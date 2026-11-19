import Foundation

/// One notification of the GATT Heart Rate Measurement characteristic (0x2A37), parsed per the Bluetooth SIG
/// Heart Rate Service specification. Platform neutral.
public struct HeartRateMeasurement: Equatable, Sendable {
    public enum SensorContact: Equatable, Sendable { case unsupported, notDetected, detected }

    public var heartRate: Int
    public var contact: SensorContact
    public var energyExpendedKJ: Int?
    /// RR intervals in milliseconds (the strap sends 1/1024 s units), oldest first.
    public var rrIntervalsMs: [Double]

    public init(heartRate: Int, contact: SensorContact = .unsupported, energyExpendedKJ: Int? = nil, rrIntervalsMs: [Double] = []) {
        self.heartRate = heartRate
        self.contact = contact
        self.energyExpendedKJ = energyExpendedKJ
        self.rrIntervalsMs = rrIntervalsMs
    }

    /// Returns nil for empty or truncated packets.
    public static func parse(_ data: Data) -> HeartRateMeasurement? {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return nil }
        let flags = bytes[0]
        var index = 1

        func read16() -> Int? {
            guard index + 2 <= bytes.count else { return nil }
            defer { index += 2 }
            return Int(bytes[index]) | (Int(bytes[index + 1]) << 8)
        }

        let heartRate: Int
        if flags & 0x01 != 0 {
            guard let v = read16() else { return nil }
            heartRate = v
        } else {
            heartRate = Int(bytes[index]); index += 1
        }

        let contact: SensorContact = flags & 0x04 == 0 ? .unsupported : (flags & 0x02 != 0 ? .detected : .notDetected)

        var energy: Int?
        if flags & 0x08 != 0 {
            guard let v = read16() else { return nil }
            energy = v
        }

        var rr: [Double] = []
        if flags & 0x10 != 0 {
            guard (bytes.count - index) % 2 == 0 else { return nil }
            while let raw = read16() { rr.append(Double(raw) * 1000.0 / 1024.0) }
            if rr.isEmpty { return nil }
        }
        return HeartRateMeasurement(heartRate: heartRate, contact: contact, energyExpendedKJ: energy, rrIntervalsMs: rr)
    }
}

/// Battery Level characteristic (0x2A19): one byte, 0–100 %.
public enum BatteryLevel {
    public static func parse(_ data: Data) -> Int? {
        guard let byte = data.first, byte <= 100 else { return nil }
        return Int(byte)
    }
}
