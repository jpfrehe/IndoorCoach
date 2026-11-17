import Foundation
import Testing
@testable import IndoorCoachKit

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return c
}()

private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 18) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}

private func ride(_ date: Date, id: Int, curve: [Int: Double]? = nil, indoor: Bool = true) -> RideSummary {
    var r = RideSummary(id: id, name: "Fahrt \(id)", sportType: indoor ? "VirtualRide" : "Ride", startDate: date,
                        movingTime: 3600, distance: 30_000, averageWatts: 150, weightedAverageWatts: 160, trainer: indoor)
    r.powerCurve = curve
    return r
}

private func point(_ date: Date, fitness: Double) -> FitnessFreshness.Point {
    FitnessFreshness.Point(date: cal.startOfDay(for: date), load: 0, fitness: fitness, fatigue: 0, form: 0)
}

/// Status with start 1 Nov 2026, CTL 40 → 60, `current`/`best` CTL and a streak of `streakWeeks` (K1 rules).
private func arc(now: Date, current: Double = 40, best: Double? = nil, streakWeeks: Int = 0) -> WinterArc.Status {
    WinterArc.status(start: at(2026, 11, 1, 0), goal: at(2027, 3, 21, 0), today: now, startCTL: 40, currentCTL: current,
                     bestCTLSinceStart: best ?? current, targetCTL: 60,
                     consistency: Consistency.Result(weeks: [], streak: streakWeeks, jokers: 0), calendar: cal)
}

@Suite("Trophäen")
struct TrophiesTests {
    // MARK: Level dates

    @Test func levelDatesComeFromTheFitnessSeries() {
        let now = at(2026, 11, 20)
        let status = arc(now: now, current: 46, best: 46)
        // 40 → 42 (10 % = level 2) on 5 Nov, 44 (level 3) on 8 Nov, dip afterwards, 46 (level 4) on 15 Nov.
        let points = [point(at(2026, 11, 2), fitness: 40.5), point(at(2026, 11, 5), fitness: 42.1),
                      point(at(2026, 11, 8), fitness: 44), point(at(2026, 11, 10), fitness: 41),
                      point(at(2026, 11, 15), fitness: 46)]
        let dates = Trophies.levelDates(status: status, points: points, calendar: cal)
        #expect(dates[1] == status.start)
        #expect(dates[2] == cal.startOfDay(for: at(2026, 11, 5)))
        #expect(dates[3] == cal.startOfDay(for: at(2026, 11, 8)))
        #expect(dates[4] == cal.startOfDay(for: at(2026, 11, 15)))
        #expect(dates[5] == nil)
    }

    @Test func aBigJumpReachesSeveralLevelsOnTheSameDay() {
        let status = arc(now: at(2026, 11, 20), current: 52, best: 52)
        let dates = Trophies.levelDates(status: status, points: [point(at(2026, 11, 12), fitness: 52)], calendar: cal)
        let day = cal.startOfDay(for: at(2026, 11, 12))
        #expect([2, 3, 4, 5, 6, 7].allSatisfy { dates[$0] == day })
        #expect(dates[8] == nil)
    }

    @Test func pointsBeforeTheSeasonStartAreIgnored() {
        let status = arc(now: at(2026, 11, 20))
        let dates = Trophies.levelDates(status: status, points: [point(at(2026, 10, 20), fitness: 58)], calendar: cal)
        #expect(dates.keys.sorted() == [1])
    }

    // MARK: All trophies

    @Test func earnedLevelsCarryTheirDates() {
        let now = at(2026, 11, 20)
        let status = arc(now: now, current: 46, best: 46)
        let points = [point(at(2026, 11, 5), fitness: 42.1), point(at(2026, 11, 8), fitness: 44), point(at(2026, 11, 15), fitness: 46)]
        let all = Trophies.all(rides: [], ftp: 250, arc: status, fitness: points, now: now, calendar: cal)
        let levels = all.filter { $0.kind == .level }
        #expect(levels.count == 10)
        #expect(levels.filter(\.isEarned).count == status.level.number)
        #expect(all.first { $0.id == "level-3" }?.earnedOn == cal.startOfDay(for: at(2026, 11, 8)))
        #expect(all.first { $0.id == "level-9" }?.isEarned == false)
        #expect(all.first { $0.id == "level-9" }?.condition == "80 % des Wegs zur Ziel-Fitness")
    }

    @Test func streakMilestonesUseTheCurrentStreak() {
        let now = at(2026, 11, 25)   // Wednesday, week starts Mon 23 Nov
        let status = arc(now: now, streakWeeks: 6)
        #expect(status.streakWeeks == 6)
        let all = Trophies.all(rides: [], ftp: 250, arc: status, fitness: [], now: now, calendar: cal)
        let four = all.first { $0.id == "streak-4" }!
        #expect(four.earnedOn == cal.startOfDay(for: at(2026, 11, 8)))   // 22 Nov (6th) − 2 weeks
        #expect(all.first { $0.id == "streak-8" }?.isEarned == false)
        #expect(all.first { $0.id == "streak-12" }?.isEarned == false)
        #expect(Trophies.streakDate(milestone: 6, streak: 6, now: now, calendar: cal) == cal.startOfDay(for: at(2026, 11, 22)))
    }

    @Test func noArcMeansNoLevelOrStreakTrophies() {
        let all = Trophies.all(rides: [], ftp: 250, arc: nil, fitness: [], now: at(2026, 11, 20), calendar: cal)
        #expect(all.allSatisfy { $0.kind != .level && $0.kind != .streak })
    }

    @Test func completedChallengeBecomesATrophyWithTheCompletionDate() {
        let now = at(2026, 11, 20)
        let rides = (0..<8).map { ride(at(2026, 11, 2 + $0), id: $0 + 1) }
        let all = Trophies.all(rides: rides, ftp: 250, arc: nil, fitness: [], now: now, calendar: cal)
        let t = all.first { $0.kind == .challenge && $0.title == "Monats-Konstanz November" }!
        #expect(t.earnedOn == at(2026, 11, 9))
        #expect(all.first { $0.kind == .challenge && $0.title == "Kalter Januar" }?.isEarned == false)
        #expect(all.filter { $0.kind == .challenge }.count == 8)
    }

    // MARK: Best efforts and 1 Hz data

    @Test func latestRecordPerDurationWins() {
        let now = at(2026, 11, 30)
        let rides = [ride(at(2026, 11, 3), id: 1, curve: [300: 250, 1200: 220]),
                     ride(at(2026, 11, 10), id: 2, curve: [300: 300, 1200: 200]),
                     ride(at(2026, 11, 17), id: 3, curve: [300: 280, 1200: 230])]
        let all = Trophies.all(rides: rides, ftp: 250, arc: nil, fitness: [], now: now, calendar: cal)
        let five = all.first { $0.id == "record-300" }!
        #expect(five.earnedOn == at(2026, 11, 10))      // ride 2 set it, ride 3 stayed below
        #expect(five.detail == "300 W · Fahrt 2")
        let twenty = all.first { $0.id == "record-1200" }!
        #expect(twenty.earnedOn == at(2026, 11, 17))    // ride 3 improved it last
        #expect(twenty.title == "Bestleistung 20 min")
        let sprint = all.first { $0.id == "record-5" }!
        #expect(!sprint.isEarned)
        #expect(!sprint.condition.isEmpty)
    }

    @Test func aSingleRideIsNoRecord() {
        let rides = [ride(at(2026, 11, 3), id: 1, curve: [300: 250])]
        let all = Trophies.all(rides: rides, ftp: 250, arc: nil, fitness: [], now: at(2026, 11, 30), calendar: cal)
        #expect(all.filter { $0.kind == .record }.allSatisfy { !$0.isEarned })
    }

    @Test func firstSecondDataRideGivesTheTrophyItsDate() {
        let rides = [ride(at(2026, 11, 1), id: 1), ride(at(2026, 11, 8), id: 2, curve: [60: 300]),
                     ride(at(2026, 11, 12), id: 3, curve: [60: 310])]
        let all = Trophies.all(rides: rides, ftp: 250, arc: nil, fitness: [], now: at(2026, 11, 30), calendar: cal)
        let t = all.first { $0.kind == .secondData }!
        #expect(t.earnedOn == at(2026, 11, 8))
        let none = Trophies.all(rides: [ride(at(2026, 11, 1), id: 1)], ftp: 250, arc: nil, fitness: [], now: at(2026, 11, 30), calendar: cal)
        #expect(none.first { $0.kind == .secondData }?.isEarned == false)
    }

    // MARK: Order and text

    @Test func earnedComeFirstNewestFirstThenLocked() {
        let now = at(2026, 11, 20)
        let rides = [ride(at(2026, 11, 8), id: 2, curve: [60: 300]), ride(at(2026, 11, 12), id: 3, curve: [60: 310])]
        let all = Trophies.all(rides: rides, ftp: 250, arc: arc(now: now), fitness: [], now: now, calendar: cal)
        let earned = all.filter(\.isEarned)
        #expect(earned.count >= 3)
        #expect(Array(all.prefix(earned.count)) == earned)
        #expect(earned.map { $0.earnedOn! } == earned.map { $0.earnedOn! }.sorted(by: >))
        #expect(all.dropFirst(earned.count).allSatisfy { !$0.isEarned })
    }

    @Test func summariesAreSpoken() {
        let locked = Trophy(id: "x", kind: .level, title: "Level 9 · Frühlingsbote", condition: "80 % des Wegs", detail: nil,
                            symbol: "bird", earnedOn: nil)
        #expect(locked.summary == "Level 9 · Frühlingsbote, noch nicht erreicht. 80 % des Wegs")
        var earned = locked
        earned.earnedOn = at(2026, 11, 8)
        #expect(earned.summary.hasPrefix("Level 9 · Frühlingsbote, erreicht am 8. November 2026"))
    }
}
