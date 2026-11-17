import Foundation

/// Fitness & Freshness (ADR-12): Banister/Coggan impulse-response model on one daily load.
///
/// Daily load per ride: power → TSS; without power and with ≥ 10 rides that have both power and an effort,
/// TSS ≈ k × Relative Effort (personal least-squares fit through the origin, like Strava); otherwise the
/// existing heart-rate / duration TSS estimate. Fitness = 42-day, Fatigue = 7-day EWMA, Form = Fitness − Fatigue
/// of the previous day.
public enum FitnessFreshness {
    public enum LoadSource: String, Sendable {
        case power, relativeEffort, estimate
    }

    public struct Load: Equatable, Sendable {
        public var value: Double
        public var source: LoadSource
    }

    public struct Point: Hashable, Sendable, Identifiable {
        public var date: Date
        public var load: Double
        public var fitness: Double
        public var fatigue: Double
        public var form: Double
        public var id: Date { date }
    }

    public enum Range: String, CaseIterable, Identifiable, Sendable {
        case days30, days90, months6, year
        public var id: String { rawValue }
        public var days: Int {
            switch self {
            case .days30: 30
            case .days90: 90
            case .months6: 182
            case .year: 365
            }
        }
        public var label: String {
            switch self {
            case .days30: "30 T"
            case .days90: "90 T"
            case .months6: "6 M"
            case .year: "1 J"
            }
        }
    }

    public struct Series: Sendable {
        public var points: [Point]
        public var effortFactor: Double?

        /// Change of fitness over the last seven days (Strava shows this next to the score).
        public var fitnessDelta7: Double {
            guard let last = points.last else { return 0 }
            let index = max(0, points.count - 8)
            return last.fitness - points[index].fitness
        }

        public func points(in range: Range) -> [Point] { Array(points.suffix(range.days)) }
    }

    public static let minimumRidesForFit = 10

    /// TSS per unit Relative Effort, fitted on rides that have both. nil below `minimumRidesForFit`.
    public static func effortToLoadFactor(rides: [RideSummary], ftp: Int,
                                          heartRate: RelativeEffort.HeartRateProfile) -> Double? {
        var pairs: [(effort: Double, tss: Double)] = []
        for ride in rides {
            let tss = TrainingLoad.estimateTSS(for: ride, ftp: ftp)
            guard tss.source == .power, let effort = RelativeEffort.estimate(for: ride, heartRate: heartRate).value,
                  effort > 0 else { continue }
            pairs.append((effort, tss.tss))
        }
        guard pairs.count >= minimumRidesForFit else { return nil }
        let numerator = pairs.reduce(0) { $0 + $1.effort * $1.tss }
        let denominator = pairs.reduce(0) { $0 + $1.effort * $1.effort }
        guard denominator > 0 else { return nil }
        let k = numerator / denominator
        return k.isFinite && k > 0 ? k : nil
    }

    public static func load(for ride: RideSummary, ftp: Int, heartRate: RelativeEffort.HeartRateProfile,
                            thresholdHeartRate: Int?, effortFactor: Double?) -> Load {
        let estimate = TrainingLoad.estimateTSS(for: ride, ftp: ftp, thresholdHeartRate: thresholdHeartRate)
        if estimate.source == .power { return Load(value: estimate.tss, source: .power) }
        if let k = effortFactor, let effort = RelativeEffort.estimate(for: ride, heartRate: heartRate).value {
            return Load(value: effort * k, source: .relativeEffort)
        }
        return Load(value: estimate.tss, source: .estimate)
    }

    public static func series(rides: [RideSummary], ftp: Int, heartRate: RelativeEffort.HeartRateProfile,
                              thresholdHeartRate: Int?, from start: Date, to end: Date,
                              calendar: Calendar = .current) -> Series {
        let k = effortToLoadFactor(rides: rides, ftp: ftp, heartRate: heartRate)
        var daily: [Date: Double] = [:]
        for ride in rides {
            daily[calendar.startOfDay(for: ride.startDate), default: 0] +=
                load(for: ride, ftp: ftp, heartRate: heartRate, thresholdHeartRate: thresholdHeartRate, effortFactor: k).value
        }
        let days = TrainingLoad.series(dailyTSS: daily, from: start, to: end, calendar: calendar)
        let points = days.map { Point(date: $0.date, load: $0.tss, fitness: $0.ctl, fatigue: $0.atl, form: $0.tsb) }
        return Series(points: points, effortFactor: k)
    }
}
