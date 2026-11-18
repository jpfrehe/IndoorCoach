import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

@Suite("Interval compliance (Soll/Ist)")
struct IntervalComplianceTests {
    static let ftp = 250

    static var sweetSpot: WorkoutDefinition {
        WorkoutDefinition(title: "Sweet Spot 2×20", type: .sweetSpot, summary: "", segments: [
            .warmup(10, from: 0.5, to: 0.7), .intervals(2, on: 1200, at: 0.9, off: 300, at: 0.55), .cooldown(8, from: 0.6, to: 0.4)
        ])
    }

    /// Ride that follows `definition` exactly (work blocks scaled by `factor`), after `lead` seconds of easy riding.
    static func ride(_ definition: WorkoutDefinition, lead: Int = 0, factor: Double = 1, ftp: Int = ftp, truncateTo: Int? = nil) -> RideSeconds {
        var watts = [Double](repeating: 100, count: lead)
        for step in definition.steps {
            for i in 0..<step.duration {
                let f = step.startPower + (step.endPower - step.startPower) * (Double(i) + 0.5) / Double(step.duration)
                watts.append(f * Double(ftp) * (f >= 0.75 ? factor : 1))
            }
        }
        if let truncateTo { watts = Array(watts.prefix(truncateTo)) }
        return RideSeconds(watts: watts, beatsPerMinute: nil)
    }

    @Test func alignsRideWithLeadIn() throws {
        let result = try #require(IntervalCompliance.analyze(definition: Self.sweetSpot, seconds: Self.ride(Self.sweetSpot, lead: 137), ftp: Self.ftp))
        #expect(result.offset == 137)
        #expect(result.intervals.count == 2)
        #expect(result.intervals.allSatisfy { $0.status == .hit })
        #expect(result.hitCount == 2 && result.total == 2)
        #expect(result.intervals[0].targetWatts == 225)
        #expect(abs(result.intervals[0].actualWatts! - 225) < 1)
        #expect(result.summary.hasPrefix("2 von 2 Intervallen getroffen"))
        #expect(result.averageCompliance > 98)
    }

    @Test func tooEasyAndTooHard() throws {
        let easy = try #require(IntervalCompliance.analyze(definition: Self.sweetSpot, seconds: Self.ride(Self.sweetSpot, factor: 0.85), ftp: Self.ftp))
        #expect(easy.intervals.allSatisfy { $0.status == .under })
        #expect(easy.hitCount == 0)
        let hard = try #require(IntervalCompliance.analyze(definition: Self.sweetSpot, seconds: Self.ride(Self.sweetSpot, factor: 1.12), ftp: Self.ftp))
        #expect(hard.intervals.allSatisfy { $0.status == .over })
        #expect(hard.intervals[0].deviation > 0.1)
    }

    @Test func borderOfTolerance() throws {
        let ok = try #require(IntervalCompliance.analyze(definition: Self.sweetSpot, seconds: Self.ride(Self.sweetSpot, factor: 1.04), ftp: Self.ftp))
        #expect(ok.hitCount == 2)
    }

    @Test func repeatsBecomeSeparateIntervals() throws {
        let def = WorkoutDefinition(title: "VO2max 5×3", type: .vo2max, summary: "", segments: [
            .warmup(10, from: 0.5, to: 0.7), .intervals(5, on: 180, at: 1.15, off: 180, at: 0.5), .cooldown(5, from: 0.6, to: 0.4)
        ])
        let result = try #require(IntervalCompliance.analyze(definition: def, seconds: Self.ride(def, lead: 60), ftp: Self.ftp))
        #expect(result.intervals.count == 5)
        #expect(result.intervals.map(\.index) == [1, 2, 3, 4, 5])
        #expect(result.intervals[0].targetWatts == 288)
    }

    @Test func shortRideMarksMissingIntervals() throws {
        // Ends in the middle of the second block's lead-in.
        let result = try #require(IntervalCompliance.analyze(definition: Self.sweetSpot, seconds: Self.ride(Self.sweetSpot, truncateTo: 600 + 1500 + 20), ftp: Self.ftp))
        #expect(result.intervals[0].status == .hit)
        #expect(result.intervals[1].status == .missed)
        #expect(result.hitCount == 1 && result.total == 2)
        #expect(result.averageCompliance < 60)
    }

    @Test func usesPassedFTP() throws {
        let seconds = Self.ride(Self.sweetSpot, ftp: 250)
        let right = try #require(IntervalCompliance.analyze(definition: Self.sweetSpot, seconds: seconds, ftp: 250))
        let raised = try #require(IntervalCompliance.analyze(definition: Self.sweetSpot, seconds: seconds, ftp: 280))
        #expect(right.hitCount == 2)
        #expect(raised.intervals[0].targetWatts == 252)
        #expect(raised.intervals.allSatisfy { $0.status == .under })
    }

    @Test func enduranceWithoutWorkIntervalsReportsBaseline() throws {
        let def = WorkoutDefinition(title: "Grundlage", type: .endurance, summary: "", segments: [.warmup(5, from: 0.5, to: 0.6), .steady(40, at: 0.65)])
        let result = try #require(IntervalCompliance.analyze(definition: def, seconds: Self.ride(def, lead: 20), ftp: Self.ftp))
        #expect(result.isBaseline)
        #expect(result.intervals.count == 1)
        #expect(result.intervals[0].status == .hit)
        #expect(result.summary.contains("Grundlage"))
    }

    @Test func emptyInputsGiveNil() {
        #expect(IntervalCompliance.analyze(definition: WorkoutDefinition(title: "", type: .mixed, summary: "", segments: []),
                                           seconds: Self.ride(Self.sweetSpot), ftp: 250) == nil)
        #expect(IntervalCompliance.analyze(definition: Self.sweetSpot, seconds: RideSeconds(power: [], heartRate: nil), ftp: 250) == nil)
        #expect(IntervalCompliance.analyze(definition: Self.sweetSpot, seconds: Self.ride(Self.sweetSpot), ftp: 0) == nil)
    }

    @Test func twoHourRideIsFast() throws {
        let def = WorkoutDefinition(title: "Lang", type: .tempo, summary: "", segments: [
            .warmup(10, from: 0.5, to: 0.7), .intervals(4, on: 1200, at: 0.9, off: 300, at: 0.55), .steady(10, at: 0.6)
        ])
        let seconds = Self.ride(def, lead: 400)
        let start = Date()
        let result = try #require(IntervalCompliance.analyze(definition: def, seconds: seconds, ftp: 250))
        #expect(Date().timeIntervalSince(start) < 2)
        #expect(result.offset == 400)
        #expect(result.total == 4)
    }

    @MainActor @Test func modelSeedLinksDoneWorkoutAndComputes() throws {
        let container = try ModelContainer(for: StoredRide.self, StoredWorkout.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(),
                             defaults: UserDefaults(suiteName: "cmp-\(UUID().uuidString)")!,
                             transport: RoutingTransport { _ in (500, Data()) }, myWhooshStore: InMemoryMyWhooshSessionStore())
        model.bootstrap()
        #expect(model.seedComplianceWorkout())
        #expect(model.seedComplianceWorkout())   // idempotent
        let workouts = try container.mainContext.fetch(FetchDescriptor<StoredWorkout>(predicate: #Predicate { $0.title == "Sweet Spot 2×20" && $0.linkedRideID != nil }))
        #expect(workouts.count == 1)
        let workout = try #require(workouts.first)
        #expect(workout.status == .done)
        let result = try #require(model.intervalCompliance(for: workout))
        #expect(result.total == 2)
        #expect(result.hitCount == 2)
        #expect(model.intervalCompliance(for: workout) == result)   // cached path

        workout.status = .planned
        #expect(model.intervalCompliance(for: workout) == nil)
        workout.status = .done
        workout.linkedRideID = nil
        #expect(model.intervalCompliance(for: workout) == nil)
    }
}
