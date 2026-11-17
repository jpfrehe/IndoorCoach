import Foundation

/// A4 "Fähigkeitslevel": level 1–10 for four durations from the power curve of the last 90 days.
///
/// The level is linear in W/kg between the band edges (low = level 1, high = level 10), rounded to the nearest
/// level and clamped to 1...10. Bands are modelled on common power-profile tables for recreational to elite riders.
///
/// | Fähigkeit | Dauer  | 1 (W/kg) | 10 (W/kg) |
/// |-----------|--------|----------|-----------|
/// | Ausdauer  | 60 min | 1.8      | 4.6       |
/// | Schwelle  | 20 min | 2.0      | 5.0       |
/// | VO2       | 5 min  | 2.5      | 6.4       |
/// | Anaerob   | 1 min  | 4.0      | 9.0       |
public enum AbilityLevels {
    public static let windowDays = 90

    public struct Band: Hashable, Sendable {
        public var name: String
        public var duration: Int
        public var lowWkg: Double
        public var highWkg: Double
        public var durationLabel: String
    }

    public static let bands: [Band] = [
        Band(name: "Ausdauer", duration: 3600, lowWkg: 1.8, highWkg: 4.6, durationLabel: "60 min"),
        Band(name: "Schwelle", duration: 1200, lowWkg: 2.0, highWkg: 5.0, durationLabel: "20 min"),
        Band(name: "VO₂", duration: 300, lowWkg: 2.5, highWkg: 6.4, durationLabel: "5 min"),
        Band(name: "Anaerob", duration: 60, lowWkg: 4.0, highWkg: 9.0, durationLabel: "1 min"),
    ]

    public struct Ability: Hashable, Sendable {
        public var band: Band
        public var watts: Double?
        public var wattsPerKg: Double?
        /// 1...10; nil without a value in the last 90 days (or without a weight).
        public var level: Int?
        /// The value is only a lower bound (summary-only rides, no measured 1 Hz curve).
        public var isFloor: Bool
        /// Level change against the 90 days before; nil unless both periods have a level.
        public var change: Int?
    }

    /// Level 1...10 for a W/kg value (linear between the band edges, rounded, clamped).
    public static func level(wattsPerKg: Double, band: Band) -> Int {
        let raw = 1 + 9 * (wattsPerKg - band.lowWkg) / (band.highWkg - band.lowWkg)
        return min(10, max(1, Int(raw.rounded())))
    }

    /// Always four entries in band order.
    public static func abilities(rides: [RideSummary], weightKg: Double, now: Date = .now) -> [Ability] {
        let length = TimeInterval(windowDays) * 86_400
        let start = now.addingTimeInterval(-length)
        let cur = PowerCurve.aggregate(rides: rides, from: start, to: now)
        let prev = PowerCurve.aggregate(rides: rides, from: start.addingTimeInterval(-length), to: start.addingTimeInterval(-1))
        return bands.map { band in
            guard weightKg > 0, let p = cur.points[band.duration] else {
                return Ability(band: band, watts: nil, wattsPerKg: nil, level: nil, isFloor: false, change: nil)
            }
            let wkg = p.watts / weightKg
            let lvl = level(wattsPerKg: wkg, band: band)
            let change = prev.points[band.duration].map { lvl - level(wattsPerKg: $0.watts / weightKg, band: band) }
            return Ability(band: band, watts: p.watts, wattsPerKg: wkg, level: lvl, isFloor: p.source == .floor, change: change)
        }
    }
}
