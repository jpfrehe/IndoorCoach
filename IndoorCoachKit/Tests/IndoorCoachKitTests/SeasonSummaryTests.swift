import Foundation
import Testing
@testable import IndoorCoachKit

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return c
}()

private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }

private func ride(_ id: Int, _ date: Date, curve20: Double?) -> RideSummary {
    var r = RideSummary(id: id, name: "R", sportType: "VirtualRide", startDate: date, movingTime: 3600, distance: 30_000,
                        averageWatts: 150, weightedAverageWatts: 160, trainer: true)
    if let curve20 { r.powerCurve = [1200: curve20, 300: curve20 + 40] }
    return r
}

private func status(now: Date) -> WinterArc.Status {
    WinterArc.status(start: day(2026, 11, 1), goal: day(2027, 3, 21), today: now, startCTL: 24, currentCTL: 34,
                     bestCTLSinceStart: 35, targetCTL: 44, calendar: cal)
}

@Suite("Saisonrückblick")
struct SeasonSummaryTests {
    @Test func collectsTheKeyNumbers() {
        let now = day(2026, 12, 20)
        let rides = [ride(1, day(2026, 10, 15), curve20: 400),       // before the season: ignored
                     ride(2, day(2026, 11, 10), curve20: 230),
                     ride(3, day(2026, 12, 1), curve20: 245)]
        let challenges = Challenges.season(rides: rides, ftp: 250, now: now, calendar: cal)
        let s = SeasonSummary.make(status: status(now: now), challenges: challenges, rides: rides, name: "  Jan ", now: now, calendar: cal)
        #expect(s.best20MinWatts == 245)
        #expect(s.best20MinText == "245 W")
        #expect(s.fitnessText == "24 → 34")
        #expect(s.levelNumber == status(now: now).level.number)
        #expect(s.challengesTotal == challenges.count)
        #expect(s.challengesCompleted == challenges.filter(\.isCompleted).count)
        #expect(s.name == "Jan")
        #expect(s.periodText == "1. Nov. – 21. März")
    }

    @Test func noNameNoPowerStaysEmpty() {
        let now = day(2026, 12, 20)
        let s = SeasonSummary.make(status: status(now: now), challenges: [], rides: [], name: "   ", now: now, calendar: cal)
        #expect(s.name == nil)
        #expect(s.best20MinWatts == nil)
        #expect(s.best20MinText == "–")
        #expect(s.challengesText == "0 von 0")
        #expect(!s.caption.contains("Jan"))
    }

    @Test func streakWording() {
        let now = day(2026, 12, 20)
        var s = SeasonSummary.make(status: status(now: now), challenges: [], rides: [], name: "", now: now, calendar: cal)
        s.streakWeeks = 1
        #expect(s.streakText == "1 Woche")
        s.streakWeeks = 5
        #expect(s.streakText == "5 Wochen")
    }
}
