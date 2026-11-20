import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

/// Direkte Nutzereingaben dürfen bei einem Speicherfehler nicht still verloren gehen: Fehler-Banner und
/// zurückgenommene Änderung, damit die Anzeige nicht etwas zeigt, das nach dem Neustart fehlt.
@MainActor
@Suite("Speicherfehler bei Nutzereingaben")
struct UserEditSaveFailureTests {
    struct DiskFull: Error {}

    let container: ModelContainer
    let model: AppModel
    let t0 = Date(timeIntervalSince1970: 1_794_000_000)

    init() throws {
        container = try AppEnvironment.makeContainer(inMemory: true)
        model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(),
                         defaults: UserDefaults(suiteName: "save-\(UUID().uuidString)")!,
                         transport: RoutingTransport { _ in (500, Data()) }, myWhooshStore: InMemoryMyWhooshSessionStore())
    }

    @Test func manualStrengthSaveFailureReportsAndLeavesNoRow() {
        model.saveOverride = { throw DiskFull() }
        let row = model.saveStrengthManual(start: t0, durationMinutes: 40, exertion: 6, legShare: .light, exercises: [])
        #expect(row == nil)
        #expect(model.banner?.isError == true)
        model.saveOverride = nil
        #expect(model.storedStrengthRows().isEmpty)
    }

    @Test func deleteStrengthSaveFailureKeepsRow() throws {
        let row = try #require(model.saveStrengthManual(start: t0, durationMinutes: 40, exertion: 6, legShare: .light, exercises: []))
        model.saveOverride = { throw DiskFull() }
        model.deleteStrength(row)
        #expect(model.banner?.isError == true)
        model.saveOverride = nil
        #expect(model.storedStrengthRows().count == 1)
    }

    @Test func perceivedExertionSaveFailureRevertsValue() throws {
        model.mergeImportedRides([RideSummary(id: -7, name: "Rolle", sportType: "VirtualRide", startDate: t0, movingTime: 3600,
                                              distance: 0, trainer: true)])
        model.saveOverride = { throw DiskFull() }
        model.setPerceivedExertion(7, prefer: true, rideID: -7)
        #expect(model.banner?.isError == true)
        model.saveOverride = nil
        #expect(model.ride(id: -7)?.perceivedExertion == nil)
    }

    @Test func workoutStatusSaveFailureRevertsStatus() throws {
        let def = WorkoutDefinition(title: "Test", type: .endurance, summary: "s", segments: [.steady(60, at: 0.6)])
        let workout = StoredWorkout(proposal: PlannedWorkoutProposal(date: t0, definition: def, rationale: ""), source: .manual, weekFocus: nil)
        container.mainContext.insert(workout)
        try container.mainContext.save()
        model.saveOverride = { throw DiskFull() }
        model.setStatus(.skipped, for: workout)
        #expect(model.banner?.isError == true)
        model.saveOverride = nil
        #expect(workout.status == .planned)
    }
}
