import Foundation
import Testing
@testable import IndoorCoachKit

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Berlin")!
    c.firstWeekday = 2
    c.minimumDaysInFirstWeek = 4
    return c
}()
private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 18) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))! }

// MARK: Gesamtwoche

private func session(_ date: Date, minutes: Int = 60, other: Bool = false, heavy: Bool = false) -> WeeklyReview.SessionItem {
    WeeklyReview.SessionItem(date: date, durationSeconds: minutes * 60, isOther: other, heavyLegs: heavy)
}

private func review(rides: [RideSummary] = [], sessions: [WeeklyReview.SessionItem]) -> WeeklyReview {
    let monday = day(2026, 11, 16, 0)
    let base = WeeklyReview.build(weekStart: monday, rides: rides, planned: [], series: FitnessFreshness.Series(points: [], effortFactor: nil),
                                  ftp: 200, thresholdHeartRate: nil, heartRate: RelativeEffort.HeartRateProfile(resting: 55, max: 190),
                                  now: day(2026, 11, 23, 9), calendar: cal)
    return base.addingSessions(sessions, calendar: cal)
}

private func rideSummary(_ date: Date, hours: Double) -> RideSummary {
    RideSummary(id: 1, name: "Fahrt", sportType: "VirtualRide", startDate: date, movingTime: Int(hours * 3600), distance: 30_000,
                averageWatts: 150, weightedAverageWatts: 160, trainer: true)
}

@Suite("Gesamtwoche")
struct WeekTotalTests {
    @Test func sumsWithoutConversion() {
        let r = review(rides: [rideSummary(day(2026, 11, 17), hours: 3)],
                       sessions: [session(day(2026, 11, 18), minutes: 60, heavy: true), session(day(2026, 11, 20), minutes: 30),
                                  session(day(2026, 11, 21), minutes: 90, other: true),
                                  session(day(2026, 11, 30))])   // other week
        #expect(r.total.strengthCount == 2)
        #expect(r.total.heavyLegCount == 1)
        #expect(r.total.otherSeconds == 5400)
        #expect(r.total.totalHours == 3 + 1.5 + 1.5)
        #expect(r.total.text == "Rad 3 h · Kraft 2× (Beine schwer 1×) · Andere 1,5 h · gesamt 6 h")
    }

    @Test func leavesOutEmptyParts() {
        let r = review(rides: [rideSummary(day(2026, 11, 17), hours: 2)], sessions: [session(day(2026, 11, 18))])
        #expect(r.total.text == "Rad 2 h · Kraft 1× · gesamt 3 h")
    }

    @Test func noSessionsMeansNoLineAndOldBehaviour() {
        let r = review(rides: [rideSummary(day(2026, 11, 17), hours: 2)], sessions: [])
        #expect(r.total.text == nil)
        #expect(!r.isEmpty)
        #expect(review(sessions: []).isEmpty)
        #expect(review(sessions: []).headline == "Ruhewoche – Erholung zählt")
    }

    @Test func strengthOnlyWeekIsNoRestWeek() {
        let r = review(sessions: [session(day(2026, 11, 18)), session(day(2026, 11, 20))])
        #expect(!r.isEmpty)
        #expect(!r.headline.contains("Ruhewoche"))
        #expect(r.sentences.first == "Gesamtwoche: Kraft 2× · gesamt 2 h")
    }
}

// MARK: Wochen-Serie

private let season = day(2026, 11, 2, 0)
private func monday(_ n: Int) -> Date { cal.date(byAdding: .day, value: 7 * n, to: season)! }
private func mid(_ n: Int, _ plus: Int = 0) -> Date { cal.date(byAdding: .day, value: 2 + plus, to: monday(n))! }

private func eval(rides: [Consistency.Ride] = [], sessions: [Consistency.Session] = [], now: Date) -> Consistency.Result {
    Consistency.evaluate(weeklyBudgetSeconds: 5 * 3600, rides: rides, planned: [], seasonStart: season, now: now, calendar: cal,
                         sessions: sessions)
}

@Suite("Wochen-Serie mit Kraft")
struct ConsistencySessionsTests {
    @Test func twoStrengthSessionsHoldTheWeek() {
        let r = eval(sessions: [.init(date: mid(0)), .init(date: mid(0, 1))], now: mid(1))
        #expect(r.weeks[0].state == .fulfilled(.sessions))
        #expect(r.streak == 1)
    }

    @Test func oneSessionOnlyIsNotEnough() {
        #expect(eval(sessions: [.init(date: mid(0))], now: mid(1)).weeks[0].state == .missed)
    }

    @Test func restWeekStaysRestWeek() {
        #expect(eval(now: mid(1)).weeks[0].state == .missed)
    }

    @Test func rideAndStrengthCountTogether() {
        let ride = Consistency.Ride(date: mid(0), seconds: 3600, tss: 50)
        #expect(eval(rides: [ride], sessions: [.init(date: mid(0, 1))], now: mid(1)).weeks[0].state == .fulfilled(.sessions))
        // Two rides alone were never enough.
        #expect(eval(rides: [ride, ride], now: mid(1)).weeks[0].state == .missed)
    }

    @Test func budgetKeepsPriorityAndDefaultIsBackwardCompatible() {
        let big = Consistency.Ride(date: mid(0), seconds: 5 * 3600, tss: 250)
        #expect(eval(rides: [big], sessions: [.init(date: mid(0)), .init(date: mid(0, 1))], now: mid(1)).weeks[0].state == .fulfilled(.budget))
        #expect(Consistency.evaluate(weeklyBudgetSeconds: 5 * 3600, rides: [], planned: [], seasonStart: season, now: mid(1), calendar: cal)
            .weeks[0].state == .missed)
    }

    @Test func runningWeekIsNeverJudged() {
        #expect(eval(sessions: [.init(date: mid(0)), .init(date: mid(0, 1))], now: mid(0, 3)).weeks[0].state == .running)
    }
}

// MARK: Kraft-Winter

@Suite("Trophäe Kraft-Winter")
struct StrengthWinterTrophyTests {
    private func arc(now: Date) -> WinterArc.Status {
        WinterArc.status(start: day(2026, 11, 1, 0), goal: day(2027, 3, 21, 0), today: now, startCTL: 40, currentCTL: 40,
                         bestCTLSinceStart: 40, targetCTL: 60,
                         consistency: Consistency.Result(weeks: [], streak: 0, jokers: 0), calendar: cal)
    }

    private func trophies(_ dates: [Date], now: Date) -> [Trophy] {
        Trophies.all(rides: [], ftp: 200, arc: arc(now: now), fitness: [], now: now, calendar: cal, strengthDates: dates)
            .filter { $0.kind == .strength }
    }

    @Test func threeTiersWithProgress() {
        let now = day(2026, 12, 20)
        let dates = (0..<9).map { day(2026, 11, 3 + $0 * 2) }
        let t = trophies(dates, now: now).sorted { $0.id < $1.id }
        #expect(t.map(\.id) == ["strengthWinter-16", "strengthWinter-24", "strengthWinter-8"])
        let eight = t.first { $0.id == "strengthWinter-8" }!
        #expect(eight.isEarned)
        #expect(eight.earnedOn == dates[7])            // date of the 8th session
        #expect(eight.title == "Kraft-Winter · 8")
        #expect(eight.condition == "8 Krafteinheiten im Winter")
        #expect(!(t.first { $0.id == "strengthWinter-16" }!.isEarned))
    }

    @Test func onlySessionsInsideTheWinterCount() {
        let outside = (0..<10).map { day(2026, 9, 1 + $0) } + [day(2027, 4, 2)]
        #expect(trophies(outside, now: day(2026, 12, 20)).allSatisfy { !$0.isEarned })
    }

    @Test func listedLockedWithoutSessions() {
        #expect(trophies([], now: day(2026, 12, 20)).count == 3)
    }
}
