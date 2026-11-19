import Foundation

/// Konstanz-Serie mit Joker und Plan-Treue (docs/10, K1). Pure: plain values in, per-week results out.
///
/// A week (ISO, Monday–Sunday) is *fulfilled* when (a) ≥ 80 % of the weekly budget was ridden, (b) every planned
/// workout of the week is done (≥ 1 planned), or (c) it is a recovery week: planned TSS < 70 % of the mean of the
/// three preceding plan weeks and ≥ 50 % of it ridden, or (d) it holds ≥ 2 units of any kind (rides, strength, other)
/// with at least one strength/other unit – a rest week with nothing stays a rest week. Every 4 fulfilled weeks in a row earn a joker (max. 2); a
/// missed week uses one automatically and the streak goes on; without a joker the streak breaks. The running week is
/// never judged.
public enum Consistency {
    public static let budgetShare = 0.8
    public static let recoveryPlanShare = 0.7
    public static let recoveryRideShare = 0.5
    public static let weeksPerJoker = 4
    public static let maxJokers = 2

    public enum Reason: String, Sendable {
        case budget, plan, recovery, sessions

        public var label: String {
            switch self {
            case .budget: "Wochenbudget erreicht"
            case .plan: "Alle geplanten Einheiten erledigt"
            case .recovery: "Erholungswoche"
            case .sessions: "Aktive Woche: Rad, Kraft & mehr"
            }
        }
    }

    public enum State: Equatable, Sendable {
        case fulfilled(Reason), joker, missed, running
    }

    /// A ride reduced to what the rules need (`tss` from `TrainingLoad.estimateTSS`).
    public struct Ride: Sendable {
        public var date: Date
        public var seconds: Double
        public var tss: Double
        public init(date: Date, seconds: Double, tss: Double) { self.date = date; self.seconds = seconds; self.tss = tss }
    }

    /// A strength or other unit (not a ride); only its date matters for the rules.
    public struct Session: Sendable {
        public var date: Date
        public init(date: Date) { self.date = date }
    }

    /// A planned workout; `done` = status done or linked to a ride.
    public struct PlannedItem: Sendable {
        public var date: Date
        public var tss: Double
        public var done: Bool
        public init(date: Date, tss: Double, done: Bool) { self.date = date; self.tss = tss; self.done = done }
    }

    public struct Adherence: Equatable, Sendable {
        public var planned: Int
        public var done: Int
        public var plannedTSS: Double
        public var rideTSS: Double

        /// Ridden TSS against planned TSS in %, nil without planned TSS.
        public var tssPercent: Int? { plannedTSS > 0 ? Int((rideTSS / plannedTSS * 100).rounded()) : nil }

        /// "3 von 4 Einheiten · 92 % TSS"; nil when nothing was planned.
        public var text: String? {
            guard planned > 0 else { return nil }
            let base = "\(done) von \(planned) Einheiten"
            guard let percent = tssPercent else { return base }
            return "\(base) · \(percent) % TSS"
        }
    }

    public struct Week: Equatable, Sendable, Identifiable {
        public var start: Date
        public var state: State
        public var hours: Double
        public var adherence: Adherence
        public var id: Date { start }
    }

    public struct Result: Equatable, Sendable {
        /// Oldest first; the last entry is the running week.
        public var weeks: [Week]
        /// Weeks in a row including joker weeks, running week excluded.
        public var streak: Int
        public var jokers: Int
        public static let empty = Result(weeks: [], streak: 0, jokers: 0)
    }

    /// "5 Wochen in Folge · 1 Joker"; nil without a streak.
    public static func summary(streak: Int, jokers: Int) -> String? {
        guard streak > 0 else { return nil }
        var text = "\(streak) \(streak == 1 ? "Woche" : "Wochen") in Folge"
        if jokers > 0 { text += " · \(jokers) Joker" }
        return text
    }

    private static func isoCalendar(_ base: Calendar) -> Calendar {
        var c = base
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }

    /// Start (Monday) of the ISO week containing `date`; the key for manually spent jokers.
    public static func weekStart(of date: Date, calendar base: Calendar = .current) -> Date {
        weekStart(date, isoCalendar(base))
    }

    private static func weekStart(_ date: Date, _ cal: Calendar) -> Date {
        cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }

    /// Plan adherence for the week starting at `weekStart` (rides and planned items of other weeks are ignored).
    public static func adherence(weekStart start: Date, rides: [Ride], planned: [PlannedItem],
                                 calendar base: Calendar = .current) -> Adherence {
        let cal = isoCalendar(base)
        let key = weekStart(start, cal)
        let plan = planned.filter { weekStart($0.date, cal) == key }
        return Adherence(planned: plan.count, done: plan.filter(\.done).count, plannedTSS: plan.reduce(0) { $0 + $1.tss },
                         rideTSS: rides.filter { weekStart($0.date, cal) == key }.reduce(0) { $0 + $1.tss })
    }

    /// Evaluates every complete week from `seasonStart` (a partial first week is skipped) up to and including the
    /// running week of `now`.
    public static func evaluate(weeklyBudgetSeconds: Double, rides: [Ride], planned: [PlannedItem], seasonStart: Date,
                                now: Date, calendar base: Calendar = .current, manualJokerWeeks: Set<Date> = [],
                                sessions: [Session] = []) -> Result {
        let cal = isoCalendar(base)
        let startDay = cal.startOfDay(for: seasonStart)
        var first = weekStart(startDay, cal)
        if first < startDay, let next = cal.date(byAdding: .weekOfYear, value: 1, to: first) { first = next }
        let current = weekStart(now, cal)
        guard first <= current else { return .empty }

        var sessionCount: [Date: Int] = [:], rideCount: [Date: Int] = [:]
        for s in sessions { sessionCount[weekStart(s.date, cal), default: 0] += 1 }
        var seconds: [Date: Double] = [:], rideTSS: [Date: Double] = [:]
        for r in rides {
            let k = weekStart(r.date, cal)
            rideCount[k, default: 0] += 1
            seconds[k, default: 0] += r.seconds
            rideTSS[k, default: 0] += r.tss
        }
        var plannedTSS: [Date: Double] = [:], plannedCount: [Date: Int] = [:], doneCount: [Date: Int] = [:]
        for p in planned {
            let k = weekStart(p.date, cal)
            plannedTSS[k, default: 0] += p.tss
            plannedCount[k, default: 0] += 1
            if p.done { doneCount[k, default: 0] += 1 }
        }

        func fulfilledReason(_ w: Date) -> Reason? {
            if weeklyBudgetSeconds > 0, seconds[w, default: 0] >= weeklyBudgetSeconds * budgetShare { return .budget }
            let count = plannedCount[w, default: 0]
            if count > 0, doneCount[w, default: 0] == count { return .plan }
            let plan = plannedTSS[w, default: 0]
            let prior = (1...3).compactMap { cal.date(byAdding: .weekOfYear, value: -$0, to: w) }
                .map { plannedTSS[$0, default: 0] }.filter { $0 > 0 }
            if plan > 0, !prior.isEmpty {
                let mean = prior.reduce(0, +) / Double(prior.count)
                if plan < mean * recoveryPlanShare, rideTSS[w, default: 0] >= plan * recoveryRideShare { return .recovery }
            }
            if sessionCount[w, default: 0] >= 1, sessionCount[w, default: 0] + rideCount[w, default: 0] >= 2 { return .sessions }
            return nil
        }

        var weeks: [Week] = []
        var streak = 0, jokers = 0, fulfilledInARow = 0
        var w = first
        while w <= current {
            let state: State
            if w == current, !manualJokerWeeks.contains(w) {
                state = .running
            } else if manualJokerWeeks.contains(w) {
                // Joker spent on purpose: the week counts as held (idempotent, the set holds each week once).
                state = .joker
                jokers = max(0, jokers - 1)
                streak += 1
                fulfilledInARow = 0
            } else if let reason = fulfilledReason(w) {
                state = .fulfilled(reason)
                streak += 1
                fulfilledInARow += 1
                if fulfilledInARow == weeksPerJoker {
                    jokers = min(maxJokers, jokers + 1)
                    fulfilledInARow = 0
                }
            } else if jokers > 0 {
                state = .joker
                jokers -= 1
                streak += 1
                fulfilledInARow = 0
            } else {
                state = .missed
                streak = 0
                fulfilledInARow = 0
            }
            weeks.append(Week(start: w, state: state, hours: seconds[w, default: 0] / 3600,
                              adherence: Adherence(planned: plannedCount[w, default: 0], done: doneCount[w, default: 0],
                                                   plannedTSS: plannedTSS[w, default: 0], rideTSS: rideTSS[w, default: 0])))
            guard let next = cal.date(byAdding: .weekOfYear, value: 1, to: w) else { break }
            w = next
        }
        return Result(weeks: weeks, streak: streak, jokers: jokers)
    }
}
