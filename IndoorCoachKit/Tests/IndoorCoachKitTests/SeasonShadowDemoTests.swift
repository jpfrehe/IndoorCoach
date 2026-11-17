import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("Vorjahres-Demo")
struct SeasonShadowDemoTests {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }

    @Test func deterministicAndDoesNotTouchRecentDemoRides() {
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 10))!
        let a = DemoData.previousYearRides(endingAt: now, calendar: cal)
        let b = DemoData.previousYearRides(endingAt: now, calendar: cal)
        #expect(a == b)
        #expect(!a.isEmpty)
        let recent = DemoData.rides(endingAt: now, calendar: cal)
        #expect(Set(a.map(\.id)).isDisjoint(with: recent.map(\.id)))
        #expect(a.allSatisfy { $0.startDate < recent.first!.startDate })
    }

    @Test func producesAShadowForTheCurrentSeasonButLowerThanToday() {
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 10))!
        let today = cal.startOfDay(for: now)
        let recent = DemoData.rides(endingAt: now, calendar: cal)
        let all = DemoData.previousYearRides(endingAt: now, calendar: cal) + recent
        let series = FitnessFreshness.series(rides: all.sorted { $0.startDate < $1.startDate }, ftp: 250,
                                             heartRate: .init(resting: 55, max: 185), thresholdHeartRate: nil,
                                             from: all.map(\.startDate).min()!, to: today, calendar: cal)
        let season = cal.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let shadow = SeasonShadow.points(from: series.points, window: season...today, calendar: cal)
        #expect(shadow != nil)
        let last = SeasonShadow.fitness(on: today, in: shadow ?? [], calendar: cal)
        #expect(last != nil)
        #expect((last ?? 0) > 10)
        #expect((last ?? 99) < (series.points.last?.fitness ?? 0))
    }
}
