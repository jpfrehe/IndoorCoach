import Foundation

/// Counters for the strap device test (B26). Holds no heart-rate or RR values and no raw device names, only
/// counts and states, so the text can go into the diagnostics export unchanged.
public struct StrapProtocolRecorder: Sendable {
    public struct Gap: Equatable, Sendable {
        /// Seconds from protocol start to the last packet before the gap.
        public var offset: Double
        public var duration: Double
        /// App was in the background when the gap ended.
        public var inBackground: Bool
    }

    public static let gapThreshold: TimeInterval = 2

    public let start: Date
    public let modelName: String
    public private(set) var packetCount = 0
    public private(set) var rrPacketCount = 0
    public private(set) var reconnects = 0
    public private(set) var gaps: [Gap] = []
    public private(set) var batteryStart: Int?
    public private(set) var batteryEnd: Int?
    private var lastPacket: Date?
    private var appActive: Bool
    private var stateSince: Date
    private var foregroundSeconds: Double = 0
    private var backgroundSeconds: Double = 0

    public init(start: Date, battery: Int?, appActive: Bool, modelName: String) {
        self.start = start
        self.batteryStart = battery
        self.batteryEnd = battery
        self.appActive = appActive
        self.stateSince = start
        self.modelName = modelName
    }

    public mutating func packet(at date: Date, hasRR: Bool) {
        if let last = lastPacket {
            let gap = date.timeIntervalSince(last)
            if gap > Self.gapThreshold {
                gaps.append(Gap(offset: last.timeIntervalSince(start), duration: gap, inBackground: !appActive))
            }
        }
        lastPacket = date
        packetCount += 1
        if hasRR { rrPacketCount += 1 }
    }

    public mutating func reconnect() { reconnects += 1 }

    public mutating func setBattery(_ level: Int) {
        if batteryStart == nil { batteryStart = level }
        batteryEnd = level
    }

    public mutating func setAppActive(_ active: Bool, at date: Date) {
        guard active != appActive else { return }
        accumulate(until: date)
        appActive = active
    }

    private mutating func accumulate(until date: Date) {
        let span = max(0, date.timeIntervalSince(stateSince))
        if appActive { foregroundSeconds += span } else { backgroundSeconds += span }
        stateSince = date
    }

    /// One line per entry (German), free of heart-rate values.
    public func reportLines(end: Date) -> [String] {
        var copy = self
        copy.accumulate(until: end)
        let total = max(0, end.timeIntervalSince(start))
        let rate = total > 0 ? Double(packetCount) / total : 0
        let longest = Int((gaps.map(\.duration).max() ?? 0).rounded())
        var lines = [
            "Gerätetest Brustgurt – Modell: \(modelName)",
            "Dauer: \(Int(total.rounded())) s",
            "Pakete: \(packetCount) (Ø \(Formatters.decimal(rate, digits: 2))/s), davon mit RR: \(rrPacketCount)",
            "Lücken > 2 s: \(gaps.count)" + (gaps.isEmpty ? "" : ", längste \(longest) s"),
            "Reconnects: \(reconnects)",
            "Akku: Start \(batteryStart.map(String.init) ?? "–") %, Ende \(batteryEnd.map(String.init) ?? "–") %",
            "App-Zustand: Vordergrund \(Int(copy.foregroundSeconds.rounded())) s, Hintergrund \(Int(copy.backgroundSeconds.rounded())) s"
        ]
        for (i, gap) in gaps.prefix(20).enumerated() {
            lines.append("Lücke \(i + 1): bei +\(Int(gap.offset.rounded())) s, \(Int(gap.duration.rounded())) s, \(gap.inBackground ? "Hintergrund" : "Vordergrund")")
        }
        return lines
    }
}
