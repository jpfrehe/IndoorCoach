import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

@Suite("Krafttraining (Store)")
@MainActor
struct StrengthStoreTests {
    static var keepAlive: [ModelContainer] = []   // ModelContext hält den Container nicht

    func makeModel(suite: String = "strength-\(UUID().uuidString)") throws -> (AppModel, ModelContainer, UserDefaults) {
        let container = try AppEnvironment.makeContainer(inMemory: true)
        Self.keepAlive.append(container)
        let defaults = UserDefaults(suiteName: suite)!
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults,
                             transport: RoutingTransport { _ in (200, Data("{}".utf8)) })
        return (model, container, defaults)
    }

    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func manualSaveRoundTrips() throws {
        let (model, _, _) = try makeModel()
        let row = model.saveStrengthManual(start: now.addingTimeInterval(-7200), durationMinutes: 50, exertion: 6, legShare: .heavy,
                                           exercises: [PerformedExercise(exerciseID: "squat", sets: 3, reps: 8, weightKg: 80)],
                                           templateName: "Beine", note: "gut")
        #expect(row != nil)
        let list = model.strengthSessions()
        #expect(list.count == 1)
        let s = try #require(list.first)
        #expect(s.source == .manual)
        #expect(s.durationSeconds == 3000)
        #expect(s.exertion == 6)
        #expect(s.legShare == .heavy)
        #expect(s.exercises.first?.weightKg == 80)
        #expect(s.templateName == "Beine")
        #expect(s.note == "gut")
    }

    @Test func manualSaveRejectsZeroDuration() throws {
        let (model, _, _) = try makeModel()
        #expect(model.saveStrengthManual(start: now, durationMinutes: 0, exertion: 5, legShare: nil, exercises: []) == nil)
        #expect(model.strengthSessions().isEmpty)
    }

    @Test func recordedSaveKeepsHeartRateAndSource() throws {
        let (model, _, _) = try makeModel()
        let hr: [UInt8] = (0..<600).map { UInt8(100 + $0 % 40) }
        let result = RecordingResult(kind: .strength, title: "Kraft", startedAt: now.addingTimeInterval(-600), endedAt: now,
                                     seconds: RideSeconds(power: Array(repeating: 0, count: 600), heartRate: hr))
        let draft = StrengthDraft(templateName: "Push", exercises: [PerformedExercise(exerciseID: "bench_press")],
                                  exertion: 7, legShare: nil, note: "")
        let row = try #require(model.saveStrength(from: result, draft: draft))
        #expect(row.source == .recorded)
        #expect(row.heartRateSeries?.count == 600)
        #expect(row.heartRateSeries?.first == 100)
        let s = row.session
        #expect(s.durationSeconds == 600)
        #expect(s.effectiveLegShare == LegInvolvement.none)
        #expect(MuscleLoad.load(of: s) == 70)
    }

    @Test func annotateIsIdempotentByHealthID() throws {
        let (model, _, _) = try makeModel()
        model.annotate(healthWorkout: "HK-1", start: now, duration: 3600, sport: "traditionalStrengthTraining", hardness: 5, legs: .light)
        model.annotate(healthWorkout: "HK-1", start: now, duration: 3600, sport: "traditionalStrengthTraining", hardness: 8, legs: .heavy)
        let list = model.strengthSessions()
        #expect(list.count == 1)
        #expect(list[0].source == .healthAnnotation)
        #expect(list[0].exertion == 8)
        #expect(list[0].legShare == .heavy)
        #expect(model.storedStrengthRows().first?.healthUUID == "HK-1")
    }

    @Test func otherSportDoesNotFeedMuscleTrackUnlessMuscular() throws {
        let (model, _, _) = try makeModel()
        _ = model.saveStrengthManual(start: now.addingTimeInterval(-3600), durationMinutes: 60, exertion: 5, legShare: nil,
                                     exercises: [], sportName: "Laufen")
        _ = model.saveStrengthManual(start: now.addingTimeInterval(-3600), durationMinutes: 60, exertion: 5, legShare: nil,
                                     exercises: [], sportName: "Bouldern")
        #expect(model.storedStrengthRows().count == 2)
        let sum = model.muscleLoad72h(now: now)
        #expect(sum.counted == 1)
        #expect(sum.total == 300)
        let boulder = try #require(model.storedStrengthRows().first { $0.sportName == "Bouldern" })
        #expect(boulder.session.effectiveLegShare == .light)
    }

    @Test func muscleLoadWindows() throws {
        let (model, _, _) = try makeModel()
        _ = model.saveStrengthManual(start: now.addingTimeInterval(-3600 * 10), durationMinutes: 60, exertion: 5, legShare: LegInvolvement.none, exercises: [])
        _ = model.saveStrengthManual(start: now.addingTimeInterval(-3600 * 100), durationMinutes: 60, exertion: 5, legShare: LegInvolvement.none, exercises: [])
        _ = model.saveStrengthManual(start: now.addingTimeInterval(-3600 * 5), durationMinutes: 30, exertion: nil, legShare: LegInvolvement.none, exercises: [])
        let sum = model.muscleLoad72h(now: now)
        #expect(sum.total == 300)
        #expect(sum.missing == 1)
    }

    @Test func deleteRemovesRow() throws {
        let (model, _, _) = try makeModel()
        let row = try #require(model.saveStrengthManual(start: now, durationMinutes: 30, exertion: 4, legShare: nil, exercises: []))
        model.deleteStrength(row)
        #expect(model.strengthSessions().isEmpty)
    }

    @Test func lastWeekTemplateUsesNewestWithExercises() throws {
        let (model, _, _) = try makeModel()
        _ = model.saveStrengthManual(start: now.addingTimeInterval(-86400 * 8), durationMinutes: 40, exertion: 5, legShare: nil,
                                     exercises: [PerformedExercise(exerciseID: "squat", sets: 3, reps: 5, weightKg: 100)], templateName: "Beine")
        _ = model.saveStrengthManual(start: now.addingTimeInterval(-86400), durationMinutes: 40, exertion: 5, legShare: nil,
                                     exercises: [PerformedExercise(exerciseID: "plank")], templateName: "Rumpf")
        let any = try #require(model.lastWeekTemplate())
        #expect(any.exerciseIDs == ["squat"])   // Vorwerte bevorzugt
        let named = try #require(model.lastWeekTemplate(named: "Rumpf"))
        #expect(named.exerciseIDs == ["plank"])
        #expect(model.lastWeekTemplate(named: "Gibtsnicht") == nil)
    }

    @Test func templatesAndDaysPersist() throws {
        let (model, container, defaults) = try makeModel()
        #expect(model.strengthTemplates().isEmpty)
        model.saveStrengthTemplate(StrengthTemplate(name: "Push", exerciseIDs: ["bench_press", "dips"]))
        model.saveStrengthTemplate(StrengthTemplate(name: "Push", exerciseIDs: ["bench_press"]))   // ersetzt gleichnamige
        model.saveStrengthTemplate(StrengthTemplate(name: "Pull", exerciseIDs: ["pull_up"]))
        #expect(model.strengthTemplates().map(\.name) == ["Push", "Pull"])
        #expect(model.strengthTemplates()[0].exerciseIDs == ["bench_press"])
        model.deleteStrengthTemplate(named: "Pull")
        #expect(model.strengthTemplates().map(\.name) == ["Push"])
        model.strengthDays = [2, 4, 9, 0]   // ungültige fliegen raus
        #expect(model.strengthDays == [2, 4])
        let again = AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults)
        #expect(again.strengthTemplates().count == 1)
        #expect(again.strengthDays == [2, 4])
    }

    @Test func strengthDoesNotChangeBikeLoad() throws {
        let (model, _, _) = try makeModel()
        model.bootstrap()
        let rides = model.context.fetchRidesForTest()
        let before = model.loadSeries(rides: rides)
        #expect(!before.isEmpty)
        _ = model.saveStrengthManual(start: .now.addingTimeInterval(-3600), durationMinutes: 90, exertion: 9, legShare: .heavy, exercises: [])
        #expect(model.loadSeries(rides: rides) == before)
    }

    @Test func deleteAllDataRemovesStrength() async throws {
        let (model, container, _) = try makeModel()
        _ = model.saveStrengthManual(start: now, durationMinutes: 30, exertion: 4, legShare: nil, exercises: [])
        model.saveStrengthTemplate(StrengthTemplate(name: "A", exerciseIDs: ["plank"]))
        model.strengthDays = [3]
        await model.deleteAllData()
        #expect(try container.mainContext.fetchCount(FetchDescriptor<StoredStrengthSession>()) == 0)
        #expect(model.strengthTemplates().isEmpty)
        #expect(model.strengthDays.isEmpty)
    }

    @Test func demoDataSeedsStrengthAndResetRemovesIt() throws {
        let (model, _, _) = try makeModel()
        model.bootstrap()
        let n = model.storedStrengthRows().count
        #expect(n >= 2 && n <= 3)
        let rows = model.storedStrengthRows()
        #expect(rows.allSatisfy { $0.isDemo })
        model.resetDemoData()
        #expect(model.storedStrengthRows().isEmpty)
    }

    @Test func schemaContainsStrength() {
        let names = AppEnvironment.schema.entities.map(\.name)
        #expect(names.contains("StoredStrengthSession"))
    }
}

private extension ModelContext {
    func fetchRidesForTest() -> [RideSummary] {
        ((try? fetch(FetchDescriptor<StoredRide>(sortBy: [SortDescriptor(\.startDate)]))) ?? []).map(\.summary)
    }
}
