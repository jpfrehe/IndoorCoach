import Foundation
import Testing
@testable import IndoorCoachKit

private let day: TimeInterval = 86_400
private let now = Date(timeIntervalSince1970: 1_794_000_000)

private func ride(_ id: Int, daysAgo: Double, minutes: Int = 60, avg: Double? = nil, maxW: Double? = nil,
                  curve: [Int: Double]? = nil) -> RideSummary {
    var r = RideSummary(id: id, name: "R\(id)", sportType: "VirtualRide", startDate: now.addingTimeInterval(-daysAgo * day),
                        movingTime: minutes * 60, distance: 20_000, averageWatts: avg, trainer: true)
    r.maxWatts = maxW
    r.powerCurve = curve
    return r
}

@Suite("PowerCurve")
struct PowerCurveTests {
    @Test func meanMaximalOfConstantSeries() {
        let curve = PowerCurve.meanMaximal(watts: Array(repeating: 200, count: 400))
        #expect(curve[1] == 200)
        #expect(curve[300] == 200)
        #expect(curve[420] == nil)          // longer than the ride
        #expect(curve[240] == 200)
    }

    @Test func meanMaximalFindsBestWindow() {
        // 100 W for 100 s, 400 W for 10 s, 100 W for 100 s
        let watts = Array(repeating: 100.0, count: 100) + Array(repeating: 400.0, count: 10) + Array(repeating: 100.0, count: 100)
        let curve = PowerCurve.meanMaximal(watts: watts)
        #expect(curve[5] == 400)
        #expect(curve[10] == 400)
        #expect(abs((curve[15] ?? 0) - (400.0 * 10 + 100 * 5) / 15) < 1e-9)
        #expect(abs((curve[60] ?? 0) - (400.0 * 10 + 100 * 50) / 60) < 1e-9)
    }

    @Test func meanMaximalHandlesEmptyAndShort() {
        #expect(PowerCurve.meanMaximal(watts: []).isEmpty)
        let c = PowerCurve.meanMaximal(watts: [100, 300])
        #expect(c[1] == 300)
        #expect(c[2] == 200)
        #expect(c[5] == nil)
    }

    @Test func floorsFromAverageAndMax() {
        let r = ride(1, daysAgo: 1, minutes: 10, avg: 200, maxW: 700)
        let floors = PowerCurve.floors(for: r)
        #expect(floors[1] == 700)
        #expect(floors[600] == 200)
        #expect(floors[300] == 200)
        #expect(floors[900] == nil)
    }

    @Test func aggregateTakesMaxAndRemembersSource() {
        let rides = [
            ride(1, daysAgo: 10, minutes: 45, avg: 205),
            ride(2, daysAgo: 5, curve: [300: 310, 1200: 260]),
            ride(3, daysAgo: 2, curve: [300: 290, 1200: 270]),
        ]
        let agg = PowerCurve.aggregate(rides: rides, from: now.addingTimeInterval(-30 * day), to: now)
        #expect(agg.points[300]?.watts == 310)
        #expect(agg.points[300]?.rideID == 2)
        #expect(agg.points[300]?.source == .measured)
        #expect(agg.points[1200]?.rideID == 3)
        #expect(agg.points[2700]?.source == .floor)     // from the 45 min / 205 W ride
        #expect(agg.points[2700]?.watts == 205)
        #expect(agg.points[3600] == nil)
    }

    @Test func measuredBeatsFloorAtEqualWatts() {
        let rides = [ride(1, daysAgo: 3, minutes: 30, avg: 250),
                     ride(2, daysAgo: 2, curve: [1200: 250])]
        let agg = PowerCurve.aggregate(rides: rides, from: now.addingTimeInterval(-30 * day), to: now)
        #expect(agg.points[1200]?.source == .measured)
        #expect(agg.points[1200]?.rideID == 2)
    }

    @Test func aggregateIgnoresRidesOutsideRange() {
        let rides = [ride(1, daysAgo: 100, curve: [300: 400]), ride(2, daysAgo: 1, curve: [300: 300])]
        let agg = PowerCurve.aggregate(rides: rides, from: now.addingTimeInterval(-42 * day), to: now)
        #expect(agg.points[300]?.watts == 300)
    }

    @Test func comparisonUsesPreviousPeriodOfEqualLength() {
        let rides = [ride(1, daysAgo: 50, curve: [300: 280]), ride(2, daysAgo: 5, curve: [300: 300])]
        let cmp = PowerCurve.comparison(rides: rides, days: 42, now: now)
        #expect(cmp.current.points[300]?.watts == 300)
        #expect(cmp.previous.points[300]?.watts == 280)
        #expect(cmp.delta(at: 300) == 20)
    }

    @Test func eftpIs95PercentOf20Min() {
        let agg = PowerCurve.aggregate(rides: [ride(1, daysAgo: 1, curve: [1200: 300])],
                                       from: now.addingTimeInterval(-day * 5), to: now)
        #expect(agg.estimatedFTP == 285)
        let none = PowerCurve.aggregate(rides: [ride(1, daysAgo: 1, curve: [300: 300])],
                                        from: now.addingTimeInterval(-day * 5), to: now)
        #expect(none.estimatedFTP == nil)
    }

    @Test func coverageCountsMeasuredVersusSummary() {
        let rides = [ride(1, daysAgo: 1, curve: [300: 300]), ride(2, daysAgo: 2, avg: 200), ride(3, daysAgo: 3, avg: 210),
                     ride(4, daysAgo: 200, curve: [300: 300])]
        let agg = PowerCurve.aggregate(rides: rides, from: now.addingTimeInterval(-30 * day), to: now)
        #expect(agg.totalRides == 3)
        #expect(agg.measuredRides == 1)
    }

    @Test func recordsFlagNewBestInLast90Days() {
        let old = ride(1, daysAgo: 30, curve: [5: 800, 300: 300])
        let best = ride(2, daysAgo: 2, curve: [5: 700, 300: 320])
        let recs = PowerCurve.records(for: best, among: [old, best], now: now)
        #expect(recs.map(\.duration) == [300])
        #expect(recs.first?.watts == 320)
        #expect(PowerCurve.records(for: old, among: [old, best], now: now).map(\.duration) == [5])
        // a ride alone in the window gets no badge
        #expect(PowerCurve.records(for: old, among: [old], now: now).isEmpty)
    }

    @Test func curveCodingRoundTrips() {
        let curve: [Int: Double] = [5: 700.5, 300: 320, 3600: 210]
        #expect(PowerCurve.decode(PowerCurve.encode(curve)) == curve)
        #expect(PowerCurve.decode(nil) == nil)
        #expect(PowerCurve.decode(Data("garbage".utf8)) == nil)
    }
}
