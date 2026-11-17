import Foundation
import Testing
@testable import IndoorCoachKit

private let now = Date(timeIntervalSince1970: 1_794_000_000)
private let day: TimeInterval = 86_400

private func ride(_ id: Int, _ daysAgo: Double, _ curve: [Int: Double]?) -> RideSummary {
    var r = RideSummary(id: id, name: "R", sportType: "VirtualRide", startDate: now.addingTimeInterval(-daysAgo * day),
                        movingTime: 3600, distance: 1, trainer: true)
    r.powerCurve = curve
    return r
}

@Suite("VO2max")
struct VO2maxTests {
    @Test func acsmFromFiveMinutePower() {
        // 300 W, 75 kg -> 4 W/kg -> 10.8 x 4 + 7 = 50.2
        #expect(abs(VO2max.fromPower(fiveMinuteWatts: 300, weightKg: 75) - 50.2) < 1e-9)
    }

    @Test func uthSorensen() {
        // 15.3 x 190 / 50 = 58.14
        #expect(abs(VO2max.fromHeartRate(maxHR: 190, restingHR: 50) - 58.14) < 1e-9)
    }

    @Test func estimatePrefersPower() {
        var profile = AthleteProfile()
        profile.weightKg = 75
        profile.maxHeartRate = 190
        let curve = PowerCurve.aggregate(rides: [ride(1, 1, [300: 300])], from: now.addingTimeInterval(-10 * day), to: now)
        let e = VO2max.estimate(curve: curve, profile: profile)
        #expect(e?.method == .power)
        #expect(abs((e?.value ?? 0) - 50.2) < 1e-9)
        #expect(e?.isLowerBound == false)
    }

    /// Review fix: a long ride's average (here 129 W, real MyWhoosh list data) must not become the VO2max input.
    @Test func longRideAverageBelowFTPProxyUsesTheFTP() {
        var profile = AthleteProfile()
        profile.weightKg = 75
        profile.ftp = 250
        var r = ride(1, 1, nil)
        r.averageWatts = 129
        let curve = PowerCurve.aggregate(rides: [r], from: now.addingTimeInterval(-10 * day), to: now)
        let e = VO2max.estimate(curve: curve, profile: profile)
        #expect(e?.method == .ftp)
        #expect(abs((e?.value ?? 0) - 50.2) < 1e-9)                     // 10.8 × (300 / 75) + 7
        #expect(e?.inputWatts == 300)
    }

    @Test func floorAboveTheFTPProxyIsUsedAsLowerBound() {
        var profile = AthleteProfile()
        profile.weightKg = 75
        profile.ftp = 150                                                // stale FTP: 1.2 × 150 = 180 W
        var r = ride(1, 1, nil)
        r.averageWatts = 200
        let curve = PowerCurve.aggregate(rides: [r], from: now.addingTimeInterval(-10 * day), to: now)
        let e = VO2max.estimate(curve: curve, profile: profile)
        #expect(e?.method == .power && e?.isLowerBound == true && e?.inputWatts == 200)
    }

    @Test func trendIgnoresSummaryFloors() {
        var profile = AthleteProfile()
        profile.weightKg = 75
        var r = ride(1, 5, nil)
        r.averageWatts = 200
        #expect(VO2max.trend(rides: [r], profile: profile, now: now).isEmpty)
    }

    @Test func fallsBackToHeartRateOnlyWithMaxHR() {
        var profile = AthleteProfile()
        profile.ftp = 0                                                  // no FTP → heart rate is the last resort
        let empty = PowerCurve.aggregate(rides: [], from: now.addingTimeInterval(-10 * day), to: now)
        #expect(VO2max.estimate(curve: empty, profile: profile) == nil)
        profile.maxHeartRate = 190
        profile.restingHeartRate = 50
        let e = VO2max.estimate(curve: empty, profile: profile)
        #expect(e?.method == .heartRate)
        #expect(abs((e?.value ?? 0) - 58.14) < 1e-9)
    }

    @Test func trendHasOneValuePerSixWeekWindow() {
        var profile = AthleteProfile()
        profile.weightKg = 75
        // windows (days ago): 0-42 ride 3, 42-84 ride 2, 84-126 ride 1, 126-168 empty
        let rides = [ride(1, 120, [300: 250]), ride(2, 80, [300: 270]), ride(3, 5, [300: 300])]
        let trend = VO2max.trend(rides: rides, profile: profile, now: now)
        #expect(trend.count == 3)
        #expect(trend.map(\.value) == trend.map(\.value).sorted())      // oldest first, improving
        #expect(trend.last.map { abs($0.value - 50.2) < 1e-9 } == true)
    }
}
