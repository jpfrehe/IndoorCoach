import Foundation

/// Aerobic efficiency: how much power you produce per heartbeat, and how stable that stays within a ride.
///
/// - EF (Efficiency Factor) = NP (else average watts) ÷ average heart rate, for comparable endurance rides only.
/// - Decoupling (Pw:HR) = EF drop from the first to the second half of a ride (needs 1 Hz power and heart rate).
public enum AerobicEfficiency {
    /// Shortest ride that counts (shorter rides are dominated by warm-up).
    public static let minimumSeconds = 20 * 60
    /// Rides harder than this are intervals/races, not comparable endurance rides.
    public static let maximumIntensity = 0.85
    /// Changes within ± this many percent count as "stable".
    public static let stableBand = 2.0
    /// Decoupling below this many percent is rated "stabil".
    public static let stableDecoupling = 5.0
    /// Weeks per comparison window of the trend.
    public static let trendWeeks = 6

    // MARK: Per ride

    /// EF of one ride, or nil when the ride has no power or heart rate, is shorter than 20 min or too intense (IF > 0.85).
    /// With `ftp <= 0` the intensity filter is skipped.
    public static func factor(for ride: RideSummary, ftp: Int) -> Double? {
        guard ride.movingTime >= minimumSeconds,
              let hr = ride.averageHeartrate, hr > 0,
              let watts = ride.weightedAverageWatts ?? ride.averageWatts, watts > 0 else { return nil }
        if ftp > 0 {
            let np = ride.weightedAverageWatts ?? (ride.averageWatts ?? 0) * 1.05
            guard np / Double(ftp) <= maximumIntensity else { return nil }
        }
        return watts / hr
    }

    // MARK: Series

    public struct WeekPoint: Hashable, Sendable, Identifiable {
        public var weekStart: Date
        /// Median EF of the qualifying rides of that week.
        public var ef: Double
        public var rides: Int
        public var id: Date { weekStart }
    }

    /// Median EF per ISO week (Monday start) for weeks that contain at least one qualifying ride, oldest first.
    public static func weeklySeries(rides: [RideSummary], ftp: Int, from start: Date, to end: Date,
                                    calendar baseCalendar: Calendar = .current) -> [WeekPoint] {
        var calendar = baseCalendar
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        var buckets: [Date: [Double]] = [:]
        for ride in rides where ride.startDate >= start && ride.startDate <= end {
            guard let ef = factor(for: ride, ftp: ftp) else { continue }
            let week = calendar.dateInterval(of: .weekOfYear, for: ride.startDate)?.start ?? calendar.startOfDay(for: ride.startDate)
            buckets[week, default: []].append(ef)
        }
        return buckets.map { WeekPoint(weekStart: $0.key, ef: median($0.value) ?? 0, rides: $0.value.count) }
            .sorted { $0.weekStart < $1.weekStart }
    }

    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    // MARK: Trend

    public enum Direction: String, Sendable { case improving, stable, declining }

    public struct Trend: Hashable, Sendable {
        /// Median EF of the last 6 weeks and of the 6 weeks before.
        public var recent: Double
        public var previous: Double
        public var changePercent: Double
        public var direction: Direction

        /// German one-liner, e.g. "+4 %: gleiche Leistung mit weniger Puls".
        public var text: String {
            let pct = Int(changePercent.rounded())
            switch direction {
            case .improving: return "+\(pct) %: gleiche Leistung mit weniger Puls"
            case .declining: return "−\(abs(pct)) %: mehr Puls für die gleiche Leistung"
            case .stable: return "Stabil (±\(Int(AerobicEfficiency.stableBand)) %): Leistung und Puls im gleichen Verhältnis"
            }
        }
    }

    /// Median EF of the last 6 weeks (ending `now`) against the 6 weeks before. nil unless both windows hold ≥ 2 rides.
    public static func trend(rides: [RideSummary], ftp: Int, now: Date = .now) -> Trend? {
        let window = Double(trendWeeks) * 7 * 86_400
        let recentStart = now.addingTimeInterval(-window), previousStart = now.addingTimeInterval(-2 * window)
        var recent: [Double] = [], previous: [Double] = []
        for ride in rides {
            guard let ef = factor(for: ride, ftp: ftp) else { continue }
            if ride.startDate > recentStart && ride.startDate <= now { recent.append(ef) }
            else if ride.startDate > previousStart && ride.startDate <= recentStart { previous.append(ef) }
        }
        guard recent.count >= 2, previous.count >= 2, let r = median(recent), let p = median(previous), p > 0 else { return nil }
        let change = (r - p) / p * 100
        let direction: Direction = change >= stableBand ? .improving : change <= -stableBand ? .declining : .stable
        return Trend(recent: r, previous: p, changePercent: change, direction: direction)
    }

    // MARK: Coverage

    public struct Coverage: Hashable, Sendable {
        /// Rides with both power and heart rate.
        public var withData: Int
        public var total: Int
        /// Rides that also qualify for EF (≥ 20 min, IF ≤ 0.85).
        public var comparable: Int
        public var fraction: Double { total > 0 ? Double(withData) / Double(total) : 0 }
        /// Too little data for a trustworthy trend: under half the rides or fewer than 4 qualifying rides.
        public var isLow: Bool { total == 0 || fraction < 0.5 || comparable < 4 }
    }

    public static func coverage(rides: [RideSummary], ftp: Int, from start: Date, to end: Date) -> Coverage {
        let inRange = rides.filter { $0.startDate >= start && $0.startDate <= end }
        let both = inRange.filter { ($0.averageHeartrate ?? 0) > 0 && ($0.weightedAverageWatts ?? $0.averageWatts ?? 0) > 0 }
        return Coverage(withData: both.count, total: inRange.count, comparable: both.filter { factor(for: $0, ftp: ftp) != nil }.count)
    }

    // MARK: Decoupling

    /// Pw:HR decoupling in percent from 1 Hz series: EF of the first half against the second half
    /// (`(EF₁ − EF₂) / EF₁ × 100`, positive = pulse drifts up against power). Seconds without heart rate (≤ 0) are ignored.
    /// nil for rides under 20 min, or when a half has heart rate for less than half of its seconds.
    public static func decoupling(power: [Double], heartRate: [Double]) -> Double? {
        let n = min(power.count, heartRate.count)
        guard n >= minimumSeconds else { return nil }
        let mid = n / 2
        func ef(_ range: Range<Int>) -> Double? {
            var p = 0.0, h = 0.0, count = 0
            for i in range where heartRate[i] > 0 { p += power[i]; h += heartRate[i]; count += 1 }
            guard count * 2 >= range.count, h > 0, p > 0 else { return nil }
            return p / h
        }
        guard let first = ef(0..<mid), let second = ef(mid..<n) else { return nil }
        return (first - second) / first * 100
    }

    public enum DecouplingRating: String, Sendable {
        case stable, slight, strong

        public var label: String {
            switch self {
            case .stable: "stabil"
            case .slight: "leichte Drift"
            case .strong: "deutliche Drift"
            }
        }
    }

    public static func rating(decoupling: Double) -> DecouplingRating {
        decoupling < stableDecoupling ? .stable : decoupling < 10 ? .slight : .strong
    }
}
