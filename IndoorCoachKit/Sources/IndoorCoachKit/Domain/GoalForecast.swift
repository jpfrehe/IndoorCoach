import Foundation

/// A5 – goal forecast: where will fitness (CTL) be on the goal day if the athlete trains `hoursPerWeek` hours?
///
/// The weekly TSS is `hours × TSS/h`, where TSS/h is the average of the last 6 weeks (fallback 50 TSS/h). It is
/// spread evenly over the days, and CTL is advanced with the same 42-day EWMA as `TrainingLoad.series`:
/// `ctl += (tss − ctl) / 42` per day.
public enum GoalForecast {
    public static let fallbackTSSPerHour = 50.0
    public static let lookbackDays = 42

    public struct DayCTL: Hashable, Sendable {
        public var date: Date
        public var ctl: Double
    }

    public struct Result: Sendable {
        public var hoursPerWeek: Double
        public var tssPerHour: Double
        public var weeklyTSS: Double
        public var targetCTL: Double
        public var ctlAtGoal: Double
        /// First day on which the projected CTL is at or above the target; nil if it stays below until the goal day.
        public var reachDate: Date?
        public var goal: Date
        /// Projected CTL, one point per day from today to the goal day.
        public var curve: [DayCTL]
        public var text: String
        /// The curve point on `reachDate` (the day the sentence names); nil if the target is already reached today or
        /// not reached before the goal day. The chart marks exactly this point.
        public var crossing: DayCTL? {
            guard let reachDate, let first = curve.first, reachDate > first.date else { return nil }
            return curve.first { $0.date == reachDate }
        }
    }

    /// Average load per hour over the last 6 weeks; `fallbackTSSPerHour` without rides in that window.
    /// Uses the same per-ride load as the fitness series (`FitnessFreshness.load`, incl. the Relative-Effort
    /// factor), so the projection continues the curve it starts from (review, main session).
    public static func tssPerHour(rides: [RideSummary], ftp: Int, thresholdHeartRate: Int?,
                                  heartRate: RelativeEffort.HeartRateProfile? = nil, now: Date) -> Double {
        let from = now.addingTimeInterval(-Double(lookbackDays) * 86_400)
        let k = heartRate.flatMap { FitnessFreshness.effortToLoadFactor(rides: rides, ftp: ftp, heartRate: $0) }
        var tss = 0.0, hours = 0.0
        for ride in rides where ride.startDate > from && ride.startDate <= now && ride.movingTime > 0 {
            tss += heartRate.map {
                FitnessFreshness.load(for: ride, ftp: ftp, heartRate: $0, thresholdHeartRate: thresholdHeartRate,
                                      effortFactor: k).value
            } ?? TrainingLoad.estimateTSS(for: ride, ftp: ftp, thresholdHeartRate: thresholdHeartRate).tss
            hours += Double(ride.movingTime) / 3600
        }
        guard hours > 0, tss > 0 else { return fallbackTSSPerHour }
        return tss / hours
    }

    /// CTL for each day from `today` (the given value) to `goal`, with `weeklyTSS / 7` on every day after today.
    public static func projection(currentCTL: Double, weeklyTSS: Double, today: Date, goal: Date,
                                  calendar: Calendar = .current) -> [DayCTL] {
        let start = calendar.startOfDay(for: today), end = calendar.startOfDay(for: goal)
        var result = [DayCTL(date: start, ctl: currentCTL)]
        guard end > start else { return result }
        let daily = max(0, weeklyTSS) / 7
        var ctl = currentCTL
        var day = start
        while day < end {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            ctl += (daily - ctl) / 42
            result.append(DayCTL(date: next, ctl: ctl))
            day = next
        }
        return result
    }

    public static func forecast(currentCTL: Double, targetCTL: Double, hoursPerWeek: Double, tssPerHour: Double,
                                today: Date, goal: Date, calendar: Calendar = .current) -> Result {
        let weekly = hoursPerWeek * tssPerHour
        let curve = projection(currentCTL: currentCTL, weeklyTSS: weekly, today: today, goal: goal, calendar: calendar)
        let atGoal = curve.last?.ctl ?? currentCTL
        let reach = curve.first { $0.ctl >= targetCTL }?.date
        let finished = calendar.startOfDay(for: goal) <= calendar.startOfDay(for: today)
        let text = sentence(hours: hoursPerWeek, ctlAtGoal: atGoal, target: targetCTL, reach: reach, goal: goal,
                            currentCTL: currentCTL, finished: finished, calendar: calendar)
        return Result(hoursPerWeek: hoursPerWeek, tssPerHour: tssPerHour, weeklyTSS: weekly, targetCTL: targetCTL,
                      ctlAtGoal: atGoal, reachDate: finished ? nil : reach, goal: goal, curve: curve, text: text)
    }

    // MARK: Text

    static func hoursText(_ hours: Double) -> String {
        let rounded = (hours * 2).rounded() / 2
        return Formatters.decimal(rounded, digits: rounded == rounded.rounded() ? 0 : 1)
    }

    /// Whether the "Heute" label has room next to the crossing label: both sit below the line, a label is about a fifth
    /// of the chart wide. With the crossing closer than that, "Heute" is left out (the dot stays).
    static func todayLabelFits(today: Date, crossing: Date?, end: Date) -> Bool {
        guard let crossing else { return true }
        let span = end.timeIntervalSince(today)
        guard span > 0 else { return true }
        return crossing.timeIntervalSince(today) / span >= 0.2
    }

    /// Short chart label for the crossing: "22. Jan." (same day as `dayText`).
    static func crossingLabel(_ date: Date, calendar: Calendar) -> String {
        DayFormatters.shared.string(from: date, format: "d. MMM", calendar: calendar)
    }

    static func dayText(_ date: Date, calendar: Calendar) -> String {
        DayFormatters.shared.string(from: date, format: "d. MMMM", calendar: calendar)
    }

    private static func sentence(hours: Double, ctlAtGoal: Double, target: Double, reach: Date?, goal: Date,
                                 currentCTL: Double, finished: Bool, calendar: Calendar) -> String {
        let h = "\(hoursText(hours)) h/Woche"
        let fitness = Formatters.decimal(ctlAtGoal)
        let targetText = Formatters.decimal(target)
        if finished { return "Der Ziel-Tag ist erreicht: Fitness \(Formatters.decimal(currentCTL)) (Ziel \(targetText))." }
        if currentCTL >= target { return "Du hast dein Ziel (Fitness \(targetText)) schon erreicht – mit \(h) hältst du es bis zum Ziel-Tag bei \(fitness)." }
        if let reach {
            let same = calendar.isDate(reach, inSameDayAs: goal)
            return "Bei \(h) erreichst du dein Ziel (Fitness \(targetText)) \(same ? "am" : "schon am") \(dayText(reach, calendar: calendar))."
        }
        return "Bei \(h) erreichst du am \(dayText(goal, calendar: calendar)) Fitness \(fitness) (Ziel \(targetText))."
    }
}

/// `DateFormatter`s are expensive to build and the chart body asks for the same label on every render: keep one per
/// format, calendar and time zone. `DateFormatter` is thread-safe; the lock only guards the dictionary.
final class DayFormatters: @unchecked Sendable {
    static let shared = DayFormatters()
    private let lock = NSLock()
    private var cache: [String: DateFormatter] = [:]

    func string(from date: Date, format: String, calendar: Calendar) -> String {
        let key = "\(format)|\(calendar.identifier)|\(calendar.timeZone.identifier)"
        lock.lock()
        defer { lock.unlock() }
        let formatter: DateFormatter
        if let cached = cache[key] {
            formatter = cached
        } else {
            formatter = DateFormatter()
            formatter.locale = Locale.de
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = format
            cache[key] = formatter
        }
        return formatter.string(from: date)
    }
}
