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
        public var totalSeconds: Int { seconds.values.reduce(0, +) }
        public func share(_ band: Band) -> Double {
            totalSeconds > 0 ? Double(seconds[band] ?? 0) / Double(totalSeconds) : 0
        }
        public func percent(_ band: Band) -> Int { Int((share(band) * 100).rounded()) }
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

    public static func distribution(rides: [RideSummary], ftp: Int, weeks: Int, now: Date) -> Result {
        let from = now.addingTimeInterval(-Double(weeks) * 7 * 86_400)
        var seconds: [Band: Int] = [:]
        var count = 0
        for ride in rides where ride.startDate > from && ride.startDate <= now && ride.movingTime > 0 {
            seconds[band(forIF: intensityFactor(for: ride, ftp: ftp)), default: 0] += ride.movingTime
            count += 1
        }
        return Result(weeks: weeks, seconds: seconds, rides: count)
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
