import Foundation
import Testing
@testable import IndoorCoachKit

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return c
}()

private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 18) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
}

/// Season start Monday 2 Nov 2026; week n (0-based) starts at Monday + 7n days.
private let season = day(2026, 11, 2, hour: 0)
private func monday(_ n: Int) -> Date { cal.date(byAdding: .day, value: 7 * n, to: season)! }
private func midweek(_ n: Int) -> Date { cal.date(byAdding: .day, value: 2, to: monday(n))! }

private let budget = 5.0 * 3600   // 5 h

private func ride(week n: Int, hours: Double, tss: Double? = nil) -> Consistency.Ride {
    Consistency.Ride(date: midweek(n), seconds: hours * 3600, tss: tss ?? hours * 50)
}

private func plan(week n: Int, tss: Double = 50, done: Bool) -> Consistency.PlannedItem {
    Consistency.PlannedItem(date: midweek(n), tss: tss, done: done)
}

private func eval(_ rides: [Consistency.Ride], _ planned: [Consistency.PlannedItem] = [], now: Date) -> Consistency.Result {
    Consistency.evaluate(weeklyBudgetSeconds: budget, rides: rides, planned: planned, seasonStart: season, now: now, calendar: cal)
}

@Suite("Konstanz")
struct ConsistencyTests {
    @Test func ruleAFulfilledWithEightyPercentOfBudget() {
        let r = eval([ride(week: 0, hours: 4), ride(week: 1, hours: 3.9)], now: midweek(2))
        #expect(r.weeks[0].state == .fulfilled(.budget))   // exactly 80 %
        #expect(r.weeks[1].state == .missed)                // 78 %, no joker yet
    }

    @Test func ruleBAllPlannedDoneEvenWithLittleTime() {
        let planned = [plan(week: 0, done: true), plan(week: 0, done: true)]
        let r = eval([ride(week: 0, hours: 1)], planned, now: midweek(1))
        #expect(r.weeks[0].state == .fulfilled(.plan))
        #expect(r.streak == 1)
    }

    @Test func ruleBNeedsAtLeastOnePlannedAndAllDone() {
        let open = eval([ride(week: 0, hours: 1)], [plan(week: 0, done: true), plan(week: 0, done: false)], now: midweek(1))
        #expect(open.weeks[0].state == .missed)
        let none = eval([ride(week: 0, hours: 1)], [], now: midweek(1))
        #expect(none.weeks[0].state == .missed)
    }

    @Test func ruleCRecoveryWeek() {
        // Three build weeks planned at 300 TSS (fulfilled by hours), then a 150-TSS recovery week.
        var planned: [Consistency.PlannedItem] = []
        var rides: [Consistency.Ride] = []
        for n in 0..<3 {
            planned.append(plan(week: n, tss: 300, done: true))
            rides.append(ride(week: n, hours: 5))
        }
        planned.append(plan(week: 3, tss: 150, done: false))      // 50 % of the mean → < 70 %
        rides.append(ride(week: 3, hours: 1.5, tss: 90))           // 60 % of the plan → ≥ 50 %
        let r = eval(rides, planned, now: midweek(4))
        #expect(r.weeks[3].state == .fulfilled(.recovery))
    }

    @Test func recoveryWeekNeedsHalfOfThePlanRidden() {
        var planned = (0..<3).map { plan(week: $0, tss: 300, done: true) }
        planned.append(plan(week: 3, tss: 150, done: false))
        var rides = (0..<3).map { ride(week: $0, hours: 5) }
        rides.append(ride(week: 3, hours: 0.5, tss: 60))           // 40 % of the plan
        let r = eval(rides, planned, now: midweek(4))
        #expect(r.weeks[3].state == .missed)
    }

    @Test func notARecoveryWeekWhenPlanIsNotMuchLighter() {
        var planned = (0..<3).map { plan(week: $0, tss: 300, done: true) }
        planned.append(plan(week: 3, tss: 250, done: false))      // 83 % of the mean
        var rides = (0..<3).map { ride(week: $0, hours: 5) }
        rides.append(ride(week: 3, hours: 3, tss: 200))
        #expect(eval(rides, planned, now: midweek(4)).weeks[3].state == .missed)
    }

    @Test func jokerEarnedAfterFourFulfilledWeeksAndUsedAutomatically() {
        let rides = (0..<4).map { ride(week: $0, hours: 5) }     // 4 fulfilled → 1 joker; week 4 empty
        let r = eval(rides, now: midweek(5))
        #expect(r.weeks.map(\.state) == [.fulfilled(.budget), .fulfilled(.budget), .fulfilled(.budget), .fulfilled(.budget), .joker, .running])
        #expect(r.streak == 5)       // four fulfilled + joker week; running week not counted
        #expect(r.jokers == 0)
    }

    @Test func jokersAreCappedAtTwo() {
        let rides = (0..<12).map { ride(week: $0, hours: 5) }
        let r = eval(rides, now: midweek(12))
        #expect(r.jokers == 2)
        #expect(r.streak == 12)
    }

    @Test func streakBreaksWithoutJoker() {
        let rides = [ride(week: 0, hours: 5), ride(week: 1, hours: 5), ride(week: 3, hours: 5)]
        let r = eval(rides, now: midweek(4))
        #expect(r.weeks[2].state == .missed)
        #expect(r.streak == 1)       // only week 3 after the break
        #expect(r.jokers == 0)
    }

    @Test func jokerWeekDoesNotCountTowardsTheNextJoker() {
        // 4 fulfilled (joker 1), joker week, then 3 fulfilled: still no new joker (needs 4 fulfilled in a row).
        let rides = (0..<4).map { ride(week: $0, hours: 5) } + (5..<8).map { ride(week: $0, hours: 5) }
        let r = eval(rides, now: midweek(8))
        #expect(r.weeks[4].state == .joker)
        #expect(r.jokers == 0)
        #expect(r.streak == 8)
    }

    @Test func runningWeekNeverBreaksTheStreak() {
        let rides = (0..<3).map { ride(week: $0, hours: 5) }
        let r = eval(rides, now: midweek(3))   // week 3 runs and is still empty
        #expect(r.weeks.last?.state == .running)
        #expect(r.streak == 3)
    }

    @Test func partialFirstWeekIsNotEvaluated() {
        let wednesdayStart = day(2026, 11, 4, hour: 0)
        let r = Consistency.evaluate(weeklyBudgetSeconds: budget, rides: [], planned: [], seasonStart: wednesdayStart,
                                     now: midweek(1), calendar: cal)
        #expect(r.weeks.first?.start == monday(1))
    }

    @Test func adherenceTextMatchesTheSpecExample() {
        // 4 planned (240 TSS), 3 done, ridden 220 TSS → 92 %.
        let planned = [plan(week: 0, tss: 60, done: true), plan(week: 0, tss: 60, done: true),
                       plan(week: 0, tss: 60, done: true), plan(week: 0, tss: 60, done: false)]
        let a = Consistency.adherence(weekStart: monday(0), rides: [ride(week: 0, hours: 4, tss: 220)], planned: planned, calendar: cal)
        #expect(a.planned == 4 && a.done == 3)
        #expect(a.tssPercent == 92)
        #expect(a.text == "3 von 4 Einheiten · 92 % TSS")
    }

    @Test func adherenceIsNilWithoutPlannedWorkouts() {
        let a = Consistency.adherence(weekStart: monday(0), rides: [ride(week: 0, hours: 4)], planned: [], calendar: cal)
        #expect(a.text == nil)
        #expect(a.tssPercent == nil)
    }

    @Test func adherenceIgnoresOtherWeeks() {
        let planned = [plan(week: 0, done: true), plan(week: 1, done: false)]
        let a = Consistency.adherence(weekStart: monday(0), rides: [ride(week: 1, hours: 2)], planned: planned, calendar: cal)
        #expect(a.planned == 1 && a.done == 1)
        #expect(a.text == "1 von 1 Einheiten · 0 % TSS")
    }

    @Test func summaryText() {
        #expect(Consistency.summary(streak: 5, jokers: 1) == "5 Wochen in Folge · 1 Joker")
        #expect(Consistency.summary(streak: 1, jokers: 0) == "1 Woche in Folge")
        #expect(Consistency.summary(streak: 0, jokers: 2) == nil)
    }
}
