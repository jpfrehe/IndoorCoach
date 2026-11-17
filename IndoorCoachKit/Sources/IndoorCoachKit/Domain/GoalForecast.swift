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
    }

    /// Average TSS per hour over the last 6 weeks; `fallbackTSSPerHour` without rides in that window.
    public static func tssPerHour(rides: [RideSummary], ftp: Int, thresholdHeartRate: Int?, now: Date) -> Double {
        let from = now.addingTimeInterval(-Double(lookbackDays) * 86_400)
        var tss = 0.0, hours = 0.0
        for ride in rides where ride.startDate > from && ride.startDate <= now && ride.movingTime > 0 {
            tss += TrainingLoad.estimateTSS(for: ride, ftp: ftp, thresholdHeartRate: thresholdHeartRate).tss
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

    static func dayText(_ date: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "d. MMMM"
        return f.string(from: date)
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
