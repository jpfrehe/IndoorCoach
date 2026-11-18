import Foundation

/// Relative Effort: cardiovascular work of an activity (Strava-like, ADR-10/11 in docs/05-FEATURES-WINTER-ARC.md).
///
/// Strava does not publish its formula. IndoorCoach uses Banister's TRIMP on average heart rate
/// (`minutes × HRr × 0.64 × e^(1.92 × HRr)`) and maps Perceived Exertion 1–10 onto the same HRr scale,
/// so both sources are comparable. Strava's own value (`suffer_score`) wins when the API provides it.
public enum RelativeEffort {
    public struct HeartRateProfile: Equatable, Sendable {
        public var resting: Int
        public var max: Int
        public init(resting: Int, max: Int) { self.resting = resting; self.max = max }
        public var isValid: Bool { resting > 25 && max > resting + 40 && max < 240 }
    }

    public enum Source: String, Sendable {
        case strava, heartRate, heartRateSeconds, perceivedExertion

        public var label: String {
            switch self {
            case .strava: "Strava"
            case .heartRate: "Herzfrequenz"
            case .heartRateSeconds: "Puls (Sekunden)"
            case .perceivedExertion: "Gefühlte Anstrengung"
            }
        }
    }

    public struct Estimate: Equatable, Sendable {
        public var value: Double?
        public var source: Source?
        public static let none = Estimate(value: nil, source: nil)
    }

    /// PE labels (Strava names only the ends: "Easy" … "Max Effort").
    public static let perceivedExertionLabels: [Int: String] = [
        1: "Sehr leicht", 2: "Leicht", 3: "Locker", 4: "Moderat", 5: "Spürbar",
        6: "Fordernd", 7: "Hart", 8: "Sehr hart", 9: "Extrem hart", 10: "Maximal",
    ]

    /// Priority: preferred PE > Strava > heart rate > PE > nothing.
    /// `secondsTRIMP` is evaluated lazily (only when the 1 Hz heart-rate path is reached) and replaces the average-HR path.
    public static func estimate(for ride: RideSummary, heartRate profile: HeartRateProfile,
                                secondsTRIMP: (() -> Double?)? = nil) -> Estimate {
        let minutes = Double(ride.movingTime) / 60
        guard minutes > 0 else { return .none }
        let pe = ride.perceivedExertion.flatMap { (1...10).contains($0) ? $0 : nil }
        if ride.preferPerceivedExertion, let pe {
            return Estimate(value: trimp(minutes: minutes, reserveFraction: reserve(forPE: pe)), source: .perceivedExertion)
        }
        if let strava = ride.stravaRelativeEffort, strava > 0 {
            return Estimate(value: strava, source: .strava)
        }
        if let value = secondsTRIMP?(), value > 0 {
            return Estimate(value: value, source: .heartRateSeconds)
        }
        if profile.isValid, let hr = ride.averageHeartrate, hr > Double(profile.resting) {
            let fraction = min(1, (hr - Double(profile.resting)) / Double(profile.max - profile.resting))
            return Estimate(value: trimp(minutes: minutes, reserveFraction: fraction), source: .heartRate)
        }
        if let pe {
            return Estimate(value: trimp(minutes: minutes, reserveFraction: reserve(forPE: pe)), source: .perceivedExertion)
        }
        return .none
    }

    /// Banister TRIMP (male coefficients, the common default for cycling software).
    public static func trimp(minutes: Double, reserveFraction hrr: Double) -> Double {
        minutes * hrr * 0.64 * exp(1.92 * hrr)
    }

    /// Per-second TRIMP: Banister summed over every second with a heart-rate sample above resting (1/60 min each).
    /// nil without a valid profile, without heart-rate seconds or when fewer than half of the seconds carry a sample.
    public static func trimp(seconds: RideSeconds, heartRate profile: HeartRateProfile) -> Double? {
        guard profile.isValid, let hr = seconds.heartRate, !hr.isEmpty else { return nil }
        let reserve = Double(profile.max - profile.resting)
        var perBPM = [Double](repeating: 0, count: 256)          // minutes-weighted TRIMP of one second at each bpm
        for bpm in (profile.resting + 1)..<256 {
            perBPM[bpm] = trimp(minutes: 1.0 / 60, reserveFraction: min(1, Double(bpm - profile.resting) / reserve))
        }
        var sum = 0.0
        var samples = 0
        for bpm in hr where bpm > 0 {
            samples += 1
            sum += perBPM[Int(bpm)]
        }
        guard samples * 2 >= hr.count else { return nil }
        return sum
    }

    /// PE 1 → 45.5 % heart-rate reserve … PE 10 → 95 %.
    public static func reserve(forPE pe: Int) -> Double { 0.40 + 0.055 * Double(pe) }

    // MARK: Weekly range

    public enum RangeStatus: String, Sendable {
        case below, within, above

        public var label: String {
            switch self {
            case .below: "Unter dem Bereich"
            case .within: "Im Bereich"
            case .above: "Über dem Bereich"
            }
        }

        public var advice: String {
            switch self {
            case .below: "Eine ruhigere Woche – gut zur Erholung oder als Anlauf."
            case .within: "Wie in den letzten drei Wochen – baut Fitness auf, ohne zu überziehen."
            case .above: "Härter als gewohnt – bringt Fortschritt, plane danach Erholung ein."
            }
        }
    }

    public struct WeeklyRange: Equatable, Sendable {
        public var average: Double
        public var lower: Double
        public var upper: Double

        public func status(for value: Double) -> RangeStatus {
            value < lower ? .below : (value > upper ? .above : .within)
        }
    }

    /// Suggested range from the average of the previous three weeks (±25 %), like Strava's white band.
    public static func weeklyRange(previousWeeks: [Double]) -> WeeklyRange? {
        let weeks = previousWeeks.suffix(3)
        guard !weeks.isEmpty else { return nil }
        let average = weeks.reduce(0, +) / Double(weeks.count)
        guard average > 0 else { return nil }
        return WeeklyRange(average: average, lower: average * 0.75, upper: average * 1.25)
    }
}
