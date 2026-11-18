import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

@Suite("Einheit anpassen (Store)")
@MainActor
struct AppModelAdjustTests {
    let definition = WorkoutDefinition(title: "Sweet Spot 2×20", type: .sweetSpot, summary: "s", segments: [
        .warmup(10, from: 0.45, to: 0.75), .intervals(2, on: 1200, at: 0.9, off: 300, at: 0.55), .cooldown(10, from: 0.65, to: 0.4)
    ])

    func makeModel(status: Int = 200) throws -> (AppModel, ModelContainer, RoutingTransport) {
        let container = try ModelContainer(for: StoredRide.self, StoredWorkout.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let transport = RoutingTransport { request in
            let body = (request.url?.path ?? "").contains("task/create") ? #"{"status":true,"data":{"id":"task-1"}}"# : #"{"message":"ok"}"#
            return (status, Data(body.utf8))
        }
        let store = MemoryMyWhooshStore(MyWhooshSession(username: "u", whooshId: "w", accessToken: "stub", refreshToken: ""))
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(),
                             defaults: UserDefaults(suiteName: "adjust-\(UUID().uuidString)")!, transport: transport, myWhooshStore: store)
        return (model, container, transport)
    }

    func makeWorkout(_ container: ModelContainer) -> StoredWorkout {
        let w = StoredWorkout(proposal: PlannedWorkoutProposal(date: .now, definition: definition, rationale: "r"),
                              source: .manual, weekFocus: nil)
        container.mainContext.insert(w)
        return w
    }

    @Test func adjustKeepsOriginalOnceAndRestores() async throws {
        let (model, container, _) = try makeModel()
        let w = makeWorkout(container)
        let originalData = w.segmentsData
        await model.adjust(w, minutes: 45, easierBy: 5)
        #expect(w.originalSegmentsData == originalData)
        #expect(abs(w.definition.totalDuration - 45 * 60) <= 60)
        #expect(w.adjustmentNote == "45 min statt 70 min · −5 % Intensität")
        #expect(model.banner?.message == "Einheit angepasst: 45 min statt 70 min · −5 % Intensität")
        // Adjusting again starts from the original, not from the already shortened version.
        await model.adjust(w, minutes: 60, easierBy: nil)
        #expect(w.originalSegmentsData == originalData)
        #expect(w.adjustmentNote == "60 min statt 70 min")
        await model.restoreOriginal(w)
        #expect(w.segmentsData == originalData)
        #expect(w.originalSegmentsData == nil && w.adjustmentNote == nil)
        #expect(w.definition.totalDuration == definition.totalDuration)
    }

    @Test func onlyPlannedWorkoutsAreAdjusted() async throws {
        let (model, container, _) = try makeModel()
        let w = makeWorkout(container)
        w.status = .done
        await model.adjust(w, minutes: 45, easierBy: nil)
        #expect(w.originalSegmentsData == nil)
        #expect(w.definition.totalDuration == definition.totalDuration)
    }

    @Test func sentWorkoutIsReplacedInMyWhoosh() async throws {
        let (model, container, transport) = try makeModel()
        let w = makeWorkout(container)
        await model.sendToMyWhoosh([w])
        #expect(w.myWhooshWorkoutID != nil)
        let before = transport.requests.count
        await model.adjust(w, minutes: 45, easierBy: nil)
        #expect(transport.requests.count > before)
        #expect(w.myWhooshSentAt != nil)
        #expect(model.banner?.isError == false)
        #expect(model.banner?.message == "Einheit angepasst: 45 min statt 70 min")
    }

    @Test func failedReplacementKeepsLocalChangeAndShowsError() async throws {
        let (model, container, transport) = try makeModel()
        let w = makeWorkout(container)
        await model.sendToMyWhoosh([w])
        let failing = RoutingTransport { _ in (500, Data("{}".utf8)) }
        _ = transport
        let model2 = AppModel(context: container.mainContext, secrets: InMemorySecretStore(),
                              defaults: UserDefaults(suiteName: "adjust-\(UUID().uuidString)")!, transport: failing,
                              myWhooshStore: MemoryMyWhooshStore(MyWhooshSession(username: "u", whooshId: "w", accessToken: "stub", refreshToken: "")))
        await model2.adjust(w, minutes: 45, easierBy: nil)
        #expect(abs(w.definition.totalDuration - 45 * 60) <= 60)
        #expect(model2.banner?.isError == true)
    }
}
