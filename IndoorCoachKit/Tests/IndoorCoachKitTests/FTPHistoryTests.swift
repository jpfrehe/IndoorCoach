import Foundation
import Testing
@testable import IndoorCoachKit

private let now = Date(timeIntervalSince1970: 1_794_000_000)

private func ride(_ id: Int, daysAgo: Double, p20: Double?) -> RideSummary {
    var r = RideSummary(id: id, name: "r", sportType: "VirtualRide", startDate: now.addingTimeInterval(-daysAgo * 86_400),
                        movingTime: 3600, distance: 0, averageWatts: 200, weightedAverageWatts: 210, trainer: true)
    if let p20 { r.powerCurve = [1200: p20, 300: p20 + 40] }
    return r
}

@Suite("eFTP history")
struct FTPHistoryTests {
    @Test func windowTakesBestMeasuredTwentyMinutes() throws {
        let rides = [ride(1, daysAgo: 3, p20: 240), ride(2, daysAgo: 10, p20: 260), ride(3, daysAgo: 20, p20: 250)]
        let last = try #require(FTPHistory.series(rides: rides, now: now).last)
        #expect(last.date == now)
        #expect(last.eftp == 247)   // 0.95 × 260
    }

    @Test func ignoresRidesWithoutMeasuredCurve() {
        // Strava-list ride: power but no 1 Hz curve → no eFTP (no floors in the history).
        #expect(FTPHistory.series(rides: [ride(1, daysAgo: 3, p20: nil)], now: now).isEmpty)
    }

    @Test func windowsAreFourWeeksWithinSixMonths() throws {
        let rides = [ride(1, daysAgo: 2, p20: 300), ride(2, daysAgo: 170, p20: 200)]
        let s = FTPHistory.series(rides: rides, now: now)
        #expect(try #require(s.first).eftp == 190)   // 0.95 × 200
        #expect(try #require(s.last).eftp == 285)    // 0.95 × 300
        #expect(s.allSatisfy { $0.date <= now && $0.date >= now.addingTimeInterval(-182 * 86_400) })
        // The 200 W ride must not leak into windows later than 28 days after it.
        let mid = s.filter { $0.date > now.addingTimeInterval(-130 * 86_400) && $0.date < now.addingTimeInterval(-30 * 86_400) }
        #expect(mid.isEmpty)
    }

    @Test func oldRideDropsOutAfterFourWeeks() {
        let s = FTPHistory.series(rides: [ride(1, daysAgo: 60, p20: 250)], now: now)
        #expect(!s.isEmpty)
        #expect(s.allSatisfy { $0.date <= now.addingTimeInterval(-32 * 86_400) })
    }
}
