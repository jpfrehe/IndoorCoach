import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

@Suite("Check-in (Store)")
@MainActor
struct CheckInStoreTests {
    let definition = WorkoutDefinition(title: "VO₂ 5×4", type: .vo2max, summary: "s", segments: [
        .warmup(15, from: 0.45, to: 0.75), .intervals(5, on: 240, at: 1.15, off: 240, at: 0.5), .cooldown(10, from: 0.65, to: 0.4)
    ])
    let bad = CheckIn.Answers(legs: .bad, sleep: .bad, mood: .ok)

    func makeModel() throws -> (AppModel, ModelContainer) {
        let container = try ModelContainer(for: StoredRide.self, StoredWorkout.self, StoredCheckIn.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(),
                             defaults: UserDefaults(suiteName: "checkin-\(UUID().uuidString)")!,
                             transport: RoutingTransport { _ in (200, Data("{}".utf8)) })
        return (model, container)
    }

    func planned(_ container: ModelContainer, date: Date = .now) -> StoredWorkout {
        let w = StoredWorkout(proposal: PlannedWorkoutProposal(date: date, definition: definition, rationale: "r"), source: .manual, weekFocus: nil)
        container.mainContext.insert(w)
        return w
    }

    @Test func dueOnlyWithPlannedWorkoutToday() throws {
        let (model, container) = try makeModel()
        #expect(!model.checkInDue())
        _ = planned(container, date: Calendar.current.date(byAdding: .day, value: 2, to: .now)!)
        #expect(!model.checkInDue())
        _ = planned(container)
        #expect(model.checkInDue())
    }

    @Test func savesOncePerDay() throws {
        let (model, container) = try makeModel()
        _ = planned(container)
        let saved = model.saveCheckIn(bad, jokersAvailable: 1)
        #expect(saved?.answers == bad)
        #expect(saved?.offered == [.shorten(minutes: 45, easierBy: 5), .swapToBase, .joker])
        #expect(model.todaysCheckIn() != nil)
        #expect(!model.checkInDue())
        #expect(model.saveCheckIn(bad, jokersAvailable: 1) == nil)
        #expect((try? container.mainContext.fetchCount(FetchDescriptor<StoredCheckIn>())) == 1)
    }

    @Test func noSaveWithoutPlannedWorkout() throws {
        let (model, container) = try makeModel()
        #expect(model.saveCheckIn(bad, jokersAvailable: 1) == nil)
        #expect((try? container.mainContext.fetchCount(FetchDescriptor<StoredCheckIn>())) == 0)
    }

    @Test func skipHidesCardAndOffersNothing() throws {
        let (model, container) = try makeModel()
        _ = planned(container)
        model.skipCheckIn()
        #expect(!model.checkInDue())
        #expect(model.todaysCheckIn()?.skipped == true)
        #expect(model.todaysCheckIn()?.offered.isEmpty == true)
    }

    @Test func shortenOfferAdjustsAndLogsChoice() async throws {
        let (model, container) = try makeModel()
        let w = planned(container)
        let saved = try #require(model.saveCheckIn(bad, jokersAvailable: 0))
        await model.applyCheckInOffer(.shorten(minutes: 45, easierBy: 5), to: w)
        #expect(abs(w.definition.totalDuration - 45 * 60) <= 60)
        #expect(w.originalSegmentsData != nil)
        #expect(saved.chosen == .shorten(minutes: 45, easierBy: 5))
    }

    @Test func swapReplacesWithBaseAndRestores() async throws {
        let (model, container) = try makeModel()
        let w = planned(container)
        let originalData = w.segmentsData
        _ = model.saveCheckIn(bad, jokersAvailable: 0)
        await model.applyCheckInOffer(.swapToBase, to: w)
        #expect(w.definition.totalDuration == definition.totalDuration)
        #expect(w.definition.segments.contains { $0.kind == .steady })
        #expect(w.originalSegmentsData == originalData)
        #expect(w.adjustmentNote?.contains("Grundlage") == true)
        #expect(w.title == "Grundlage 65 min (getauscht)")
        #expect(w.type == .endurance)
        #expect(model.todaysCheckIn()?.chosen == .swapToBase)
        await model.restoreOriginal(w)
        #expect(w.segmentsData == originalData)
        #expect(w.title == "VO₂ 5×4")
        #expect(w.type == .vo2max)
        #expect(w.originalTitle == nil && w.originalTypeRaw == nil)
    }

    @Test func restoreAfterPlainAdjustKeepsTitleAndType() async throws {
        let (model, container) = try makeModel()
        let w = planned(container)
        await model.adjust(w, minutes: 45, easierBy: nil)
        await model.restoreOriginal(w)
        #expect(w.title == "VO₂ 5×4" && w.type == .vo2max)
    }

    @Test func swapAfterAdjustKeepsTrueOriginal() async throws {
        let (model, container) = try makeModel()
        let w = planned(container)
        let originalData = w.segmentsData
        await model.adjust(w, minutes: 45, easierBy: nil)
        await model.applyCheckInOffer(.swapToBase, to: w)
        #expect(w.originalSegmentsData == originalData)
        #expect(w.originalTitle == "VO₂ 5×4" && w.originalTypeRaw == "vo2max")
        await model.applyCheckInOffer(.swapToBase, to: w)   // second swap must not overwrite the true original
        #expect(w.originalTitle == "VO₂ 5×4")
    }

    /// Four fulfilled past weeks (all planned done) earn one joker.
    func earnJoker(_ model: AppModel, _ container: ModelContainer, now: Date = .now) {
        let cal = Calendar.current
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: now)!.start
        model.profile.arcStart = cal.date(byAdding: .weekOfYear, value: -5, to: thisWeek)
        for n in 1...4 {
            let w = planned(container, date: cal.date(byAdding: .weekOfYear, value: -n, to: thisWeek)!.addingTimeInterval(3 * 86400))
            w.status = .done
        }
    }

    @Test func jokerOfferUsesJokerForCurrentWeek() async throws {
        let (model, container) = try makeModel()
        earnJoker(model, container)
        let w = planned(container)
        let data = w.segmentsData
        #expect(model.consistency(rides: []).jokers == 1)
        _ = model.saveCheckIn(bad, jokersAvailable: 1)
        await model.applyCheckInOffer(.joker, to: w)
        #expect(w.segmentsData == data)
        #expect(model.todaysCheckIn()?.chosen == .joker)
        #expect(model.consistency(rides: []).jokers == 0)
        #expect(model.consistency(rides: []).weeks.last?.state == .joker)
    }

    @Test func useJokerIsIdempotentPerWeek() throws {
        let (model, container) = try makeModel()
        earnJoker(model, container)
        #expect(model.useJoker(rides: []))
        #expect(model.useJoker(rides: []))
        #expect(model.consistency(rides: []).jokers == 0)
    }

    @Test func useJokerFailsWithoutJoker() throws {
        let (model, container) = try makeModel()
        withExtendedLifetime(container) {}
        #expect(!model.useJoker(rides: []))
        #expect(model.consistency(rides: []).weeks.last?.state != .joker)
        withExtendedLifetime(container) {}
    }

    @Test func schemaContainsCheckIn() {
        let names = AppEnvironment.schema.entities.map(\.name)
        #expect(names.contains("StoredCheckIn") && names.contains("StoredWorkout") && names.contains("StoredRide"))
    }
}
