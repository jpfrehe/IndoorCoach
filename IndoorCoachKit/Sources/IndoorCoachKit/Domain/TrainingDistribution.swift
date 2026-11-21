import Foundation

/// A8 – training distribution: the share of riding time per intensity band over 4 or 12 weeks.
///
/// Per ride the intensity factor is IF = NP ÷ FTP (NP = weighted average power, else average power × 1.05).
/// Bands: Grundlage IF < 0.75, Tempo/Sweet Spot 0.75 … < 0.95, Schwelle+ ≥ 0.95; rides without power or FTP
/// count as "unbekannt". The whole ride counts in the band of its IF, weighted by moving time.
public enum TrainingDistribution {
    public enum Band: String, CaseIterable, Identifiable, Sendable {
        case base, tempo, threshold, unknown
        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .base: "Grundlage"
            case .tempo: "Tempo / Sweet Spot"
            case .threshold: "Schwelle und mehr"
            case .unknown: "Unbekannt (ohne Leistung)"
            }
        }
        public var shortLabel: String {
            switch self {
            case .base: "Grundlage"
            case .tempo: "Tempo"
            case .threshold: "Schwelle+"
            case .unknown: "Unbekannt"
            }
        }
    }

    public struct Result: Sendable {
        public var weeks: Int
        public var seconds: [Band: Int]
        public var rides: Int
        /// Rides whose time per band comes from 1 Hz data (the rest is estimated from the ride's IF).
        public var measuredRides: Int = 0
        public var estimatedRides: Int { rides - measuredRides }
        public var totalSeconds: Int { seconds.values.reduce(0, +) }
        public func share(_ band: Band) -> Double {
            totalSeconds > 0 ? Double(seconds[band] ?? 0) / Double(totalSeconds) : 0
        }
        public func percent(_ band: Band) -> Int { Int((share(band) * 100).rounded()) }
    }

    /// Share text inside a tall bar segment ("46 %"), or nil when the segment is empty or too narrow for it
    /// (text width plus 12 pt padding).
    static func segmentLabel(percent: Int, barWidth: Double, textWidth: Double) -> String? {
        guard percent > 0, barWidth > 0 else { return nil }
        return barWidth * Double(percent) / 100 >= textWidth + 12 ? "\(percent) %" : nil
    }

    public static func intensityFactor(for ride: RideSummary, ftp: Int) -> Double? {
        guard ftp > 0, let np = ride.weightedAverageWatts ?? ride.averageWatts.map({ $0 * 1.05 }), np > 0 else { return nil }
        return np / Double(ftp)
    }

    public static func band(forIF intensity: Double?) -> Band {
        guard let intensity else { return .unknown }
        if intensity < 0.75 { return .base }
        return intensity < 0.95 ? .tempo : .threshold
    }

    /// Rides for which `zoneTimes` returns 1 Hz zone data contribute their actual seconds per band (power bands cut at
    /// the IF thresholds 0,75 / 0,95, 0 W seconds excluded); all others the whole ride in the band of its IF.
    public static func distribution(rides: [RideSummary], ftp: Int, weeks: Int, now: Date,
                                    zoneTimes: (RideSummary) -> ZoneTime.Result? = { _ in nil }) -> Result {
        let from = now.addingTimeInterval(-Double(weeks) * 7 * 86_400)
        var seconds: [Band: Int] = [:]
        var count = 0
        var measured = 0
        for ride in rides where ride.startDate > from && ride.startDate <= now && ride.movingTime > 0 {
            count += 1
            if let zones = zoneTimes(ride), zones.powerTotal > 0 {
                seconds[.base, default: 0] += zones.bands[0]
                seconds[.tempo, default: 0] += zones.bands[1]
                seconds[.threshold, default: 0] += zones.bands[2]
                measured += 1
            } else {
                seconds[band(forIF: intensityFactor(for: ride, ftp: ftp)), default: 0] += ride.movingTime
            }
        }
        return Result(weeks: weeks, seconds: seconds, rides: count, measuredRides: measured)
    }

    /// Short advice for the winter base phase. The shares are those shown in the bar (of all riding time).
    public static func advice(_ r: Result) -> String {
        guard r.totalSeconds > 0 else { return "Noch keine Fahrten in diesem Zeitraum." }
        if r.share(.unknown) >= 0.5 {
            return "Bei über der Hälfte deiner Fahrzeit fehlt die Leistung – die Verteilung ist nur ein grober Anhaltspunkt."
        }
        let base = r.percent(.base)
        if r.share(.base) >= 0.7 { return "\(base) % Grundlage – passt zum Winter" }
        if r.share(.tempo) + r.share(.threshold) > 0.4 { return "Viel Intensität: plane mehr lockere Einheiten" }
        return "\(base) % Grundlage – im Winter darf es gern etwas mehr lockere Fahrzeit sein"
    }
}
