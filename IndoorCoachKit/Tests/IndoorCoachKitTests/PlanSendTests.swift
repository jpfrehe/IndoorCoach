import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

@MainActor
@Suite("Alle senden · intervals.icu")
struct PlanSendTests {
    let container: ModelContainer
    let model: AppModel
    let transport = RoutingTransport { request in
        request.url?.path == "/api/v1/athlete/0" ? (200, Data(#"{"id":"i1","name":"Jan"}"#.utf8)) : (200, Data("[]".utf8))
    }
    let definition = WorkoutDefinition(title: "Sweet Spot", type: .sweetSpot, summary: "s", segments: [
        .warmup(10, from: 0.45, to: 0.75), .intervals(2, on: 1200, at: 0.9, off: 300, at: 0.55), .cooldown(10, from: 0.65, to: 0.4)])

    init() throws {
        container = try AppEnvironment.makeContainer(inMemory: true)
        model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(),
                         defaults: UserDefaults(suiteName: "plansend-\(UUID().uuidString)")!, transport: transport,
                         myWhooshStore: InMemoryMyWhooshSessionStore(), intervalsConfig: IntervalsConfig(clientID: ""))
    }

    @discardableResult
    func add(daysAhead: Int, status: WorkoutStatus = .planned) -> StoredWorkout {
        let date = Calendar.current.date(byAdding: .day, value: daysAhead, to: .now)!
        let w = StoredWorkout(proposal: PlannedWorkoutProposal(date: date, definition: definition, rationale: "r"), source: .manual, weekFocus: nil)
        w.status = status
        container.mainContext.insert(w)
        return w
    }

    @Test func nothingPlannedShowsABannerAndSendsNothing() async {
        await model.connectIntervals(apiKey: "key-123456")
        let before = transport.requests.count
        add(daysAhead: -3); add(daysAhead: 2, status: .done)
        await model.sendUpcomingToIntervals()
        #expect(model.banner?.message == "Keine geplanten Einheiten zum Senden.")
        #expect(transport.requests.count == before)
    }

    @Test func onlyUpcomingPlannedWorkoutsAreSent() async throws {
        await model.connectIntervals(apiKey: "key-123456")
        let old = add(daysAhead: -3), done = add(daysAhead: 2, status: .done)
        let a = add(daysAhead: 1), b = add(daysAhead: 4)
        await model.sendUpcomingToIntervals()
        #expect(a.intervalsSentAt != nil && b.intervalsSentAt != nil)
        #expect(old.intervalsSentAt == nil && done.intervalsSentAt == nil)
        let bulk = try #require(transport.requests.last { $0.url?.path.hasSuffix("/events/bulk") == true })
        let body = try #require(bulk.httpBody)
        let array = try #require(try JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        #expect(array.count == 2)
    }
}
