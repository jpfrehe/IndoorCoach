import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

private let zNow = Date(timeIntervalSince1970: 1_794_000_000)

@Suite("Time in zones")
struct ZoneTimeTests {
    @Test func powerZoneBoundariesAndPausesExcluded() {
        // FTP 200: Z1 <112, Z2 <152, Z3 <182, Z4 <212, Z5 <242, Z6 <302, Z7 above.
        let power: [UInt16] = [0, 0, 111, 112, 151, 152, 181, 182, 211, 212, 241, 242, 301, 302, 900]
        let r = ZoneTime.compute(RideSeconds(power: power, heartRate: nil), ftp: 200, heartRate: nil)
        #expect(r.power == [1, 2, 2, 2, 2, 2, 2])          // the two 0 W seconds are not counted
        #expect(r.powerTotal == 13)
        #expect(r.heart == nil)
    }

    @Test func bandsFollowTheIntensityFactorThresholds() {
        // FTP 200: base < 150 W, tempo 150 … < 190 W, threshold ≥ 190 W.
        let r = ZoneTime.compute(RideSeconds(power: [149, 150, 189, 190, 0], heartRate: nil), ftp: 200, heartRate: nil)
        #expect(r.bands == [1, 2, 1])
    }

    @Test func heartRateZonesFromMaxAndFromThreshold() throws {
        let byMax = HeartRateZones(maxHeartRate: 200, thresholdHeartRate: nil)
        #expect(byMax.zone(forBPM: 119) == 0)
        #expect(byMax.zone(forBPM: 120) == 1)
        #expect(byMax.zone(forBPM: 140) == 2)
        #expect(byMax.zone(forBPM: 160) == 3)
        #expect(byMax.zone(forBPM: 180) == 4)
        let byLTHR = HeartRateZones(maxHeartRate: 200, thresholdHeartRate: 170)
        #expect(byLTHR.zone(forBPM: 137) == 0)      // < 81 % of 170 = 137.7
        #expect(byLTHR.zone(forBPM: 138) == 1)
        #expect(byLTHR.zone(forBPM: 170) == 4)
        let r = ZoneTime.compute(RideSeconds(power: [100, 100, 100, 100], heartRate: [0, 100, 150, 190]), ftp: 200, heartRate: byMax)
        #expect(r.heart == [1, 0, 1, 0, 1])           // 0 bpm excluded
        #expect(r.heartTotal == 3)
        let none = ZoneTime.compute(RideSeconds(power: [100], heartRate: nil), ftp: 200, heartRate: byMax)
        #expect(none.heart == nil)
    }

    @Test func zeroFTPYieldsNoPowerZones() {
        let r = ZoneTime.compute(RideSeconds(power: [100, 200], heartRate: nil), ftp: 0, heartRate: nil)
        #expect(r.powerTotal == 0)
    }

    @Test func secondBasedTRIMPMatchesAverageHeartRateForSteadyRides() throws {
        let profile = RelativeEffort.HeartRateProfile(resting: 50, max: 190)
        let seconds = RideSeconds(power: Array(repeating: 200, count: 3600), heartRate: Array(repeating: 140, count: 3600))
        let perSecond = try #require(RelativeEffort.trimp(seconds: seconds, heartRate: profile))
        var ride = RideSummary(id: 1, name: "r", sportType: "VirtualRide", startDate: zNow, movingTime: 3600, distance: 0,
                               averageWatts: 200, trainer: true)
        ride.averageHeartrate = 140
        let average = try #require(RelativeEffort.estimate(for: ride, heartRate: profile).value)
        #expect(abs(perSecond - average) < 0.01)
    }

    @Test func secondBasedTRIMPIsHigherForVariableRidesAndNeedsCoverage() throws {
        let profile = RelativeEffort.HeartRateProfile(resting: 50, max: 190)
        let hr = Array(repeating: UInt8(110), count: 1800) + Array(repeating: UInt8(170), count: 1800)
        let seconds = RideSeconds(power: Array(repeating: 200, count: 3600), heartRate: hr)
        let perSecond = try #require(RelativeEffort.trimp(seconds: seconds, heartRate: profile))
        let avg = RelativeEffort.trimp(minutes: 60, reserveFraction: (140.0 - 50) / 140)
        #expect(perSecond > avg)                      // TRIMP is convex in HR reserve
        let sparse = RideSeconds(power: Array(repeating: 200, count: 3600),
                                 heartRate: Array(repeating: 0, count: 3500) + Array(repeating: 150, count: 100))
        #expect(RelativeEffort.trimp(seconds: sparse, heartRate: profile) == nil)
        #expect(RelativeEffort.trimp(seconds: seconds, heartRate: .init(resting: 0, max: 0)) == nil)
    }

    @Test func estimateUsesSecondsAfterPEAndStravaButBeforeAverageHR() throws {
        let profile = RelativeEffort.HeartRateProfile(resting: 50, max: 190)
        var ride = RideSummary(id: 1, name: "r", sportType: "VirtualRide", startDate: zNow, movingTime: 3600, distance: 0, trainer: true)
        ride.averageHeartrate = 140
        let e = RelativeEffort.estimate(for: ride, heartRate: profile, secondsTRIMP: { 77 })
        #expect(e.source == .heartRateSeconds)
        #expect(e.value == 77)
        #expect(RelativeEffort.Source.heartRateSeconds.label == "Puls (Sekunden)")
        ride.stravaRelativeEffort = 90
        #expect(RelativeEffort.estimate(for: ride, heartRate: profile, secondsTRIMP: { 77 }).source == .strava)
        ride.stravaRelativeEffort = nil
        #expect(RelativeEffort.estimate(for: ride, heartRate: profile, secondsTRIMP: { nil }).source == .heartRate)
    }

    @Test func distributionUsesActualTimePerBandAndCountsMeasured() {
        let rides = [
            RideSummary(id: 1, name: "a", sportType: "VirtualRide", startDate: zNow.addingTimeInterval(-86_400), movingTime: 3600,
                        distance: 0, averageWatts: 200, weightedAverageWatts: 200, trainer: true),   // IF 0.8 → whole ride tempo
            RideSummary(id: 2, name: "b", sportType: "VirtualRide", startDate: zNow.addingTimeInterval(-2 * 86_400), movingTime: 3600,
                        distance: 0, averageWatts: 100, weightedAverageWatts: 100, trainer: true),
        ]
        let measured = ZoneTime.compute(RideSeconds(power: Array(repeating: 100, count: 1800) + Array(repeating: 200, count: 600),
                                                    heartRate: nil), ftp: 250, heartRate: nil)
        let r = TrainingDistribution.distribution(rides: rides, ftp: 250, weeks: 4, now: zNow) { $0.id == 1 ? measured : nil }
        #expect(r.measuredRides == 1)
        #expect(r.estimatedRides == 1)
        #expect(r.rides == 2)
        // ride 1 measured: 1800 s base (0.4), 600 s tempo (0.8); ride 2 estimated: 3600 s base (IF 0.4)
        #expect(r.seconds[.base] == 1800 + 3600)
        #expect(r.seconds[.tempo] == 600)
    }

    @Test func legacyDistributionAPIUnchangedAndMeasuredIsZero() {
        let ride = RideSummary(id: 1, name: "a", sportType: "VirtualRide", startDate: zNow.addingTimeInterval(-86_400), movingTime: 3600,
                               distance: 0, weightedAverageWatts: 150, trainer: true)
        let r = TrainingDistribution.distribution(rides: [ride], ftp: 250, weeks: 4, now: zNow)
        #expect(r.measuredRides == 0 && r.estimatedRides == 1)
    }

    @MainActor @Test func modelCachesZoneTimesAndDistributionIsFast() throws {
        let container = try ModelContainer(for: StoredRide.self, StoredWorkout.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(),
                             defaults: UserDefaults(suiteName: "zones-\(UUID().uuidString)")!,
                             transport: RoutingTransport { _ in (500, Data()) }, myWhooshStore: InMemoryMyWhooshSessionStore())
        model.profile.ftp = 250
        var rides: [RideSummary] = []
        var secs: [Int: RideSeconds] = [:]
        for i in 0..<60 {
            let ride = RideSummary(id: 1000 + i, name: "r\(i)", sportType: "VirtualRide",
                                   startDate: zNow.addingTimeInterval(-Double(i) * 86_400 / 4), movingTime: 3600, distance: 0,
                                   averageWatts: 180, weightedAverageWatts: 190, trainer: true)
            rides.append(ride)
            secs[ride.id] = DemoData.syntheticSeconds(for: ride, ftp: 250)
        }
        _ = model.mergeImportedRides(rides, seconds: secs)
        let clock = ContinuousClock()
        let t = clock.measure {
            let r = model.trainingDistribution(rides: rides, weeks: 12, now: zNow)
            #expect(r.measuredRides == 60)
        }
        #expect(t < .milliseconds(500))
        let first = try #require(model.zoneTimes(for: rides[0]))
        #expect(first.powerTotal > 3000)
        #expect(model.zoneTimes(for: rides[0]) == first)
        model.profile.ftp = 300
        #expect(model.zoneTimes(for: rides[0]) != first)    // FTP is part of the cache key
    }
}
