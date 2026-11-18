import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("Ride merge")
struct RideMergeTests {
    private let start = Date(timeIntervalSince1970: 1_794_000_000)

    private func listRide(id: Int = 1, start: Date, avgHR: Double? = nil) -> RideSummary {
        RideSummary(id: id, name: "MyWhoosh Grundlage", sportType: "VirtualRide", startDate: start, movingTime: 3600,
                    distance: 30_000, averageWatts: 200, averageHeartrate: avgHR, trainer: true)
    }

    private func fitRide(id: Int = -5, start: Date) -> RideSummary {
        var r = RideSummary(id: id, name: "MyNewActivity-1.2", sportType: "VirtualRide", startDate: start, movingTime: 3590,
                            distance: 31_000, averageWatts: 205, weightedAverageWatts: 221, kilojoules: 738,
                            averageHeartrate: 138, maxHeartrate: 171, trainer: true)
        r.maxWatts = 640
        r.powerCurve = [1: 640, 300: 280]
        r.decoupling = 3.2
        r.durability = 97
        return r
    }

    @Test func insertsWhenNothingStartsNearby() {
        let existing = [listRide(start: start.addingTimeInterval(-3600))]
        #expect(RideMerge.decide(fitRide(start: start), existing: existing) == .insert)
        #expect(RideMerge.decide(fitRide(start: start), existing: []) == .insert)
    }

    @Test func enrichesARideStartingWithinFiveMinutes() {
        let later = [listRide(id: 7, start: start.addingTimeInterval(240))]
        #expect(RideMerge.decide(fitRide(start: start), existing: later) == .enrich(7))
        let earlier = [listRide(id: 7, start: start.addingTimeInterval(-299))]
        #expect(RideMerge.decide(fitRide(start: start), existing: earlier) == .enrich(7))
    }

    @Test func fiveMinutesOrMoreIsAnotherRide() {
        let existing = [listRide(start: start.addingTimeInterval(300))]
        #expect(RideMerge.decide(fitRide(start: start), existing: existing) == .insert)
    }

    @Test func picksTheClosestRide() {
        let existing = [listRide(id: 1, start: start.addingTimeInterval(200)), listRide(id: 2, start: start.addingTimeInterval(-30))]
        #expect(RideMerge.decide(fitRide(start: start), existing: existing) == .enrich(2))
    }

    @Test func sameIDCountsAsTheSameRide() {
        let existing = [listRide(id: -5, start: start.addingTimeInterval(-7200))]
        #expect(RideMerge.decide(fitRide(id: -5, start: start), existing: existing) == .enrich(-5))
    }

    @Test func aRideWithACurveIsAlreadyComplete() {
        var have = listRide(id: 3, start: start)
        have.powerCurve = [1: 500]
        #expect(RideMerge.decide(fitRide(start: start), existing: [have]) == .alreadyComplete(3))
    }

    @Test func listRidesWithoutSecondsDataStayDuplicates() {
        let existing = [listRide(id: 3, start: start)]
        #expect(RideMerge.decide(listRide(id: 9, start: start.addingTimeInterval(60)), existing: existing) == .duplicate(3))
        var curved = existing[0]
        curved.powerCurve = [1: 500]
        #expect(RideMerge.decide(listRide(id: 9, start: start), existing: [curved]) == .alreadyComplete(3))
    }

    @Test func enrichmentFillsSecondsDataAndKeepsTheRidesIdentity() {
        var existing = listRide(id: 7, start: start.addingTimeInterval(120))
        existing.name = "Meine Fahrt"
        existing.perceivedExertion = 6
        existing.preferPerceivedExertion = true
        existing.stravaRelativeEffort = 55
        existing.weightedAverageWatts = 190      // Strava estimate
        existing.maxWatts = 600

        let merged = RideMerge.enriched(existing, with: fitRide(start: start))
        #expect(merged.id == 7 && merged.name == "Meine Fahrt")
        #expect(merged.startDate == existing.startDate && merged.movingTime == 3600 && merged.distance == 30_000)
        #expect(merged.perceivedExertion == 6 && merged.preferPerceivedExertion && merged.stravaRelativeEffort == 55)
        #expect(merged.powerCurve == [1: 640, 300: 280])
        #expect(merged.maxWatts == 640)
        #expect(merged.weightedAverageWatts == 221)
        #expect(merged.decoupling == 3.2 && merged.durability == 97)
        #expect(merged.kilojoules == 738)
        #expect(merged.averageHeartrate == 138 && merged.maxHeartrate == 171)
        #expect(merged.averageWatts == 200)       // already known: untouched
    }

    @Test func existingHeartRateAndHigherMaxSurvive() {
        var existing = listRide(id: 7, start: start, avgHR: 150)
        existing.maxWatts = 900
        let merged = RideMerge.enriched(existing, with: fitRide(start: start))
        #expect(merged.averageHeartrate == 150)
        #expect(merged.maxWatts == 900)
    }

    @Test func missingAverageWattsAreTakenFromTheFile() {
        var existing = listRide(id: 7, start: start)
        existing.averageWatts = nil
        #expect(RideMerge.enriched(existing, with: fitRide(start: start)).averageWatts == 205)
    }

    @Test func enrichingWithoutNewDataChangesNothing() {
        let existing = listRide(id: 7, start: start)
        #expect(RideMerge.enriched(existing, with: listRide(id: 9, start: start)) == existing)
    }
}
