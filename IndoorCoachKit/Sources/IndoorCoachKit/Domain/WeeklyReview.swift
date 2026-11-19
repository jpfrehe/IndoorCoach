import Foundation

/// Wochenrückblick (Konstanz-Paket K2): numbers and rule-based German texts for one ISO week (Mon–Sun).
/// Pure value logic – no persistence, no network, no Claude call.
public struct WeeklyReview: Equatable, Sendable, Identifiable {
    /// A planned workout reduced to what the review needs (the caller leaves out skipped ones).
    public struct PlannedItem: Equatable, Sendable {
        public var date: Date
        public var tss: Double
        public var done: Bool
        public init(date: Date, tss: Double, done: Bool) { self.date = date; self.tss = tss; self.done = done }
    }

    public struct Record: Equatable, Sendable {
        public var duration: Int
        public var watts: Double
        public var rideID: Int
    }

    /// A strength or other unit reduced to what the week total needs.
    public struct SessionItem: Equatable, Sendable {
        public var date: Date
        public var durationSeconds: Int
        /// „Andere Einheit“ (nicht Krafttraining).
        public var isOther: Bool
        public var heavyLegs: Bool
        public init(date: Date, durationSeconds: Int, isOther: Bool, heavyLegs: Bool) {
            self.date = date; self.durationSeconds = durationSeconds; self.isOther = isOther; self.heavyLegs = heavyLegs
        }
    }

    /// Stunden und Anzahl je Art, einfach addiert – keine Umrechnung zwischen Rad und Kraft.
    public struct WeekTotal: Equatable, Sendable {
        public var rideSeconds: Double
        public var strengthCount: Int
        public var strengthSeconds: Double
        public var heavyLegCount: Int
        public var otherCount: Int
        public var otherSeconds: Double
        public static let empty = WeekTotal(rideSeconds: 0, strengthCount: 0, strengthSeconds: 0, heavyLegCount: 0,
                                            otherCount: 0, otherSeconds: 0)

        public var hasSessions: Bool { strengthCount > 0 || otherCount > 0 }
        public var totalHours: Double { (rideSeconds + strengthSeconds + otherSeconds) / 3600 }

        /// „Rad 3 h · Kraft 2× (Beine schwer 1×) · Andere 1,5 h · gesamt 6 h“; nil ohne Kraft/Andere.
        public var text: String? {
            guard hasSessions else { return nil }
            var parts: [String] = []
            if rideSeconds > 0 { parts.append("Rad \(Self.hours(rideSeconds / 3600))") }
            if strengthCount > 0 {
                parts.append("Kraft \(strengthCount)×" + (heavyLegCount > 0 ? " (Beine schwer \(heavyLegCount)×)" : ""))
            }
            if otherCount > 0 { parts.append("Andere \(Self.hours(otherSeconds / 3600))") }
            parts.append("gesamt \(Self.hours(totalHours))")
            return parts.joined(separator: " · ")
        }

        static func hours(_ value: Double) -> String {
            let rounded = (value * 10).rounded() / 10
            return (rounded == rounded.rounded() ? Formatters.decimal(rounded) : Formatters.decimal(rounded, digits: 1)) + " h"
        }
    }

    /// Local midnight of the Monday.
    public var weekStart: Date
    public var rideCount: Int
    public var hours: Double
    public var actualTSS: Double
    public var plannedCount: Int
    public var doneCount: Int
    public var plannedTSS: Double
    /// Fitness (CTL) at the end of the week minus at the start of it; nil without a series.
    public var fitnessChange: Double?
    /// Form (TSB) on the last day of the week; nil without a series.
    public var form: Double?
    public var effortTotal: Double
    public var effortRange: RelativeEffort.WeeklyRange?
    public var records: [Record]
    public var headline: String
    public var sentences: [String]
    /// Gesamtwoche (Rad, Kraft, Andere); leer, bis `addingSessions` sie füllt.
    public var total: WeekTotal = .empty

    public var id: Date { weekStart }
    /// Ruhewoche: weder Fahrt noch Kraft- oder andere Einheit.
    public var isEmpty: Bool { rideCount == 0 && !total.hasSessions }
    /// done ÷ planned; nil when nothing was planned.
    public var adherence: Double? { plannedCount > 0 ? Double(doneCount) / Double(plannedCount) : nil }
    public var effortStatus: RelativeEffort.RangeStatus? { effortRange?.status(for: effortTotal) }

    // MARK: Calendar & window

    /// The caller's calendar (time zone, locale) forced to ISO weeks, Monday first.
    static func isoCalendar(_ base: Calendar) -> Calendar {
        var calendar = base
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    public static func weekStart(containing date: Date, calendar: Calendar = .current) -> Date {
        let iso = isoCalendar(calendar)
        return iso.dateInterval(of: .weekOfYear, for: date)?.start ?? iso.startOfDay(for: date)
    }

    /// Monday of the week whose review is due: from Sunday 16:00 through Tuesday 23:59:59 (local time).
    /// Sunday afternoon → the current week, Monday/Tuesday → the week that just ended, otherwise nil.
    public static func visibleWeekStart(now: Date, calendar: Calendar = .current) -> Date? {
        let iso = isoCalendar(calendar)
        let weekday = AthleteProfile.isoWeekday(of: now, calendar: iso)
        let current = weekStart(containing: now, calendar: iso)
        switch weekday {
        case 7: return iso.component(.hour, from: now) >= 16 ? current : nil
        case 1, 2: return iso.date(byAdding: .weekOfYear, value: -1, to: current)
        default: return nil
        }
    }

    // MARK: Builder

    public static func build(weekStart: Date, rides: [RideSummary], planned: [PlannedItem], series: FitnessFreshness.Series,
                             ftp: Int, thresholdHeartRate: Int?, heartRate: RelativeEffort.HeartRateProfile,
                             now: Date = .now, calendar: Calendar = .current) -> WeeklyReview {
        let iso = isoCalendar(calendar)
        let start = weekStart
        let next = iso.date(byAdding: .weekOfYear, value: 1, to: start) ?? start.addingTimeInterval(7 * 86_400)
        func inWeek(_ date: Date) -> Bool { date >= start && date < next }

        let weekRides = rides.filter { inWeek($0.startDate) }
        let seconds = weekRides.reduce(0) { $0 + $1.movingTime }
        let tss = weekRides.reduce(0.0) {
            $0 + TrainingLoad.estimateTSS(for: $1, ftp: ftp, thresholdHeartRate: thresholdHeartRate).tss
        }
        let weekPlan = planned.filter { inWeek($0.date) }

        func effort(in from: Date, to: Date) -> Double {
            rides.filter { $0.startDate >= from && $0.startDate < to }
                .reduce(0.0) { $0 + (RelativeEffort.estimate(for: $1, heartRate: heartRate).value ?? 0) }
        }
        let previousTotals: [Double] = (1...3).reversed().compactMap { back in
            guard let from = iso.date(byAdding: .weekOfYear, value: -back, to: start),
                  let to = iso.date(byAdding: .weekOfYear, value: -back + 1, to: start) else { return nil }
            return effort(in: from, to: to)
        }

        // Fitness: value on the last day before the week (0 when the series starts inside it) → last day of the week.
        let before = series.points.last { $0.date < start }
        let last = series.points.last { $0.date < next }
        var change: Double?
        var form: Double?
        if let last, last.date >= start {
            change = last.fitness - (before?.fitness ?? 0)
            form = last.form
        }

        // Records are judged as of the end of the week (or now, for the running week).
        let judged = min(now, next.addingTimeInterval(-1))
        var bestByDuration: [Int: Record] = [:]
        for ride in weekRides {
            for p in PowerCurve.records(for: ride, among: rides, now: judged) where p.watts > (bestByDuration[p.duration]?.watts ?? 0) {
                bestByDuration[p.duration] = Record(duration: p.duration, watts: p.watts, rideID: p.rideID)
            }
        }

        var review = WeeklyReview(
            weekStart: start, rideCount: weekRides.count, hours: Double(seconds) / 3600, actualTSS: tss,
            plannedCount: weekPlan.count, doneCount: weekPlan.filter(\.done).count, plannedTSS: weekPlan.reduce(0) { $0 + $1.tss },
            fitnessChange: change, form: form,
            effortTotal: effort(in: start, to: next), effortRange: RelativeEffort.weeklyRange(previousWeeks: previousTotals),
            records: bestByDuration.values.sorted { $0.duration < $1.duration }, headline: "", sentences: [])
        review.headline = review.makeHeadline()
        review.sentences = review.makeSentences()
        return review
    }

    /// The `count` weeks ending at `endingAt` (a Monday), newest first.
    public static func recent(count: Int, endingAt focus: Date, rides: [RideSummary], planned: [PlannedItem],
                              series: FitnessFreshness.Series, ftp: Int, thresholdHeartRate: Int?,
                              heartRate: RelativeEffort.HeartRateProfile, now: Date = .now,
                              calendar: Calendar = .current) -> [WeeklyReview] {
        let iso = isoCalendar(calendar)
        return (0..<max(count, 0)).compactMap { back in
            iso.date(byAdding: .weekOfYear, value: -back, to: focus).map {
                build(weekStart: $0, rides: rides, planned: planned, series: series, ftp: ftp,
                      thresholdHeartRate: thresholdHeartRate, heartRate: heartRate, now: now, calendar: calendar)
            }
        }
    }

    /// Ergänzt die Gesamtwoche um Kraft- und andere Einheiten dieser Woche. Eine Woche ohne Fahrt, aber mit Einheiten
    /// ist keine Ruhewoche: Überschrift und Sätze nennen dann die Gesamtwoche.
    public func addingSessions(_ items: [SessionItem], calendar: Calendar = .current) -> WeeklyReview {
        let iso = Self.isoCalendar(calendar)
        let next = iso.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart.addingTimeInterval(7 * 86_400)
        let week = items.filter { $0.date >= weekStart && $0.date < next }
        let strength = week.filter { !$0.isOther }
        let other = week.filter(\.isOther)
        var copy = self
        copy.total = WeekTotal(rideSeconds: hours * 3600, strengthCount: strength.count,
                               strengthSeconds: Double(strength.reduce(0) { $0 + max(0, $1.durationSeconds) }),
                               heavyLegCount: strength.filter(\.heavyLegs).count, otherCount: other.count,
                               otherSeconds: Double(other.reduce(0) { $0 + max(0, $1.durationSeconds) }))
        if rideCount == 0, let line = copy.total.text {
            let n = copy.total.strengthCount + copy.total.otherCount
            copy.headline = "Aktive Woche ohne Rad: \(n) \(n == 1 ? "Einheit" : "Einheiten")"
            copy.sentences = ["Gesamtwoche: " + line, "Erholung vom Rad gehört dazu – Kraft und andere Einheiten zählen mit."]
        }
        return copy
    }

    // MARK: Texts

    private func makeHeadline() -> String {
        if isEmpty { return "Ruhewoche – Erholung zählt" }
        if plannedCount > 0 {
            if doneCount >= plannedCount {
                return plannedCount == 1 ? "Starke Woche: die geplante Einheit gefahren"
                                         : "Starke Woche: alle \(plannedCount) Einheiten gefahren"
            }
            let word = (adherence ?? 0) >= 0.5 ? "Solide" : "Kurze"
            return "\(word) Woche: \(doneCount) von \(plannedCount) Einheiten gefahren"
        }
        return "Gut drangeblieben: \(rideCount) \(rideCount == 1 ? "Fahrt" : "Fahrten")"
    }

    private func makeSentences() -> [String] {
        if isEmpty {
            return ["Diese Woche stand das Rad still – das ist völlig in Ordnung, Erholung gehört zum Training.",
                    "Wenn du magst, startest du die neue Woche mit einer lockeren Einheit."]
        }
        var all: [String] = []
        var volume = "\(Formatters.duration(Int((hours * 3600).rounded()))) gefahren, \(Int(actualTSS.rounded())) TSS"
        if plannedTSS > 0 { volume += " – \(Int((actualTSS / plannedTSS * 100).rounded())) % vom Plan" }
        all.append(volume)
        if let change = fitnessChange, let form {
            all.append("Fitness \(Self.signed(change, digits: 1)) – Form jetzt \(Self.formWord(form)) (\(Self.signed(form, digits: 0)))")
        }
        if !records.isEmpty {
            let parts = records.map { "\(Self.durationLabel($0.duration)) mit \(Int($0.watts.rounded())) W" }
            all.append(records.count == 1 ? "Neue Bestleistung: \(parts[0])"
                                          : "Neue Bestleistungen: " + parts.joined(separator: ", "))
        }
        if effortTotal > 0 {
            let value = Formatters.decimal(effortTotal)
            switch effortStatus {
            case .below: all.append("Relative Effort \(value) – etwas unter deinem üblichen Bereich")
            case .within: all.append("Relative Effort \(value) – im üblichen Bereich")
            case .above: all.append("Relative Effort \(value) – über deinem üblichen Bereich")
            case nil: all.append("Relative Effort \(value)")
            }
        }
        return Array(all.prefix(3))
    }

    static func signed(_ value: Double, digits: Int) -> String {
        let rounded = Formatters.decimal(abs(value), digits: digits)
        let isZero = Double(rounded.replacingOccurrences(of: ",", with: ".")) == 0
        if isZero { return rounded }
        return (value < 0 ? "−" : "+") + rounded
    }

    /// Same thresholds and words as the form chip on Heute (single source: `FitnessFreshness.formLabel`).
    static func formWord(_ tsb: Double) -> String { FitnessFreshness.formLabel(tsb).lowercased() }

    static func durationLabel(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        if seconds < 3600 { return "\(seconds / 60) min" }
        return seconds % 3600 == 0 ? "\(seconds / 3600) h" : "\(seconds / 60) min"
    }
}
