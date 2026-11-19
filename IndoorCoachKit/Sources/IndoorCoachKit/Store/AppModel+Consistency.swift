import Foundation
import SwiftData

extension AppModel {
    /// Konstanz-Serie (K1): evaluates the weeks since the Winter Arc start from rides and the saved plan.
    public func consistency(rides: [RideSummary], now: Date = .now) -> Consistency.Result {
        let calendar = Calendar.current
        let season = WinterArc.defaultSeason(containing: now, calendar: calendar)
        let start = calendar.startOfDay(for: profile.arcStart ?? season.start)
        return Consistency.evaluate(weeklyBudgetSeconds: profile.weeklyHours * 3600,
                                    rides: consistencyRides(rides.filter { $0.startDate >= start }),
                                    planned: consistencyPlanned(), seasonStart: start, now: now, calendar: calendar,
                                    manualJokerWeeks: manualJokerWeeks, sessions: consistencySessions())
    }

    static let manualJokerKey = Keys.manualJokerWeeks

    /// Weeks (Monday) in which the rider spent a joker on purpose; lives in UserDefaults.
    var manualJokerWeeks: Set<Date> {
        Set((defaults.array(forKey: Self.manualJokerKey) as? [Double] ?? []).map { Date(timeIntervalSince1970: $0) })
    }

    /// Spends a joker for the current week: the week counts as held. Idempotent per week; false without an available joker.
    @discardableResult
    public func useJoker(rides: [RideSummary], now: Date = .now) -> Bool {
        let week = Consistency.weekStart(of: now)
        var weeks = manualJokerWeeks
        if weeks.contains(week) { return true }
        guard consistency(rides: rides, now: now).jokers > 0 else { return false }
        weeks.insert(week)
        defaults.set(weeks.map(\.timeIntervalSince1970), forKey: Self.manualJokerKey)
        return true
    }

    func consistencyRides(_ rides: [RideSummary]) -> [Consistency.Ride] {
        rides.map {
            Consistency.Ride(date: $0.startDate, seconds: Double($0.movingTime),
                             tss: TrainingLoad.estimateTSS(for: $0, ftp: profile.ftp, thresholdHeartRate: profile.thresholdHeartRate).tss)
        }
    }

    func consistencyPlanned() -> [Consistency.PlannedItem] {
        ((try? context.fetch(FetchDescriptor<StoredWorkout>())) ?? []).map {
            Consistency.PlannedItem(date: $0.date, tss: $0.definition.estimatedTSS, done: $0.status == .done || $0.linkedRideID != nil)
        }
    }

    /// Kraft- und andere Einheiten für die Wochen-Serie (≥ 2 Einheiten beliebiger Art halten die Woche).
    func consistencySessions() -> [Consistency.Session] {
        ((try? context.fetch(FetchDescriptor<StoredStrengthSession>())) ?? []).map { Consistency.Session(date: $0.start) }
    }

    /// Beginn aller Krafteinheiten (ohne „Andere Einheiten“) für die Trophäe Kraft-Winter.
    func strengthSessionDates() -> [Date] {
        ((try? context.fetch(FetchDescriptor<StoredStrengthSession>())) ?? []).filter { !$0.isOtherSport }.map(\.start)
    }
}
