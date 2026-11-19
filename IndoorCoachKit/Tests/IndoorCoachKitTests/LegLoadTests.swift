import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

/// W3-C (B49): Claude kennt die Woche, Banner „Schwere Beine – tauschen?“.
@Suite("Schwere Beine (Plan-Kontext, Banner)")
@MainActor
struct LegLoadTests {
    static var keepAlive: [ModelContainer] = []
    let cal = Calendar.current

    func makeModel(suite: String = "legload-\(UUID().uuidString)") throws -> (AppModel, ModelContainer) {
        let container = try AppEnvironment.makeContainer(inMemory: true)
        Self.keepAlive.append(container)
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(),
                             defaults: UserDefaults(suiteName: suite)!,
                             transport: RoutingTransport { _ in (200, Data("{}".utf8)) })
        return (model, container)
    }

    /// Heute 12:00 lokal.
    var noon: Date { cal.date(bySettingHour: 12, minute: 0, second: 0, of: cal.startOfDay(for: .now))! }
    func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: .now))! }

    @discardableResult
    func addWorkout(_ container: ModelContainer, type: WorkoutType, title: String, dayOffset: Int) -> StoredWorkout {
        let seg: [Segment] = [.warmup(10, from: 0.45, to: 0.7), .steady(40, at: type == .endurance ? 0.65 : 0.95),
                              .cooldown(5, from: 0.6, to: 0.4)]
        let def = WorkoutDefinition(title: title, type: type, summary: "s", segments: seg)
        let w = StoredWorkout(proposal: PlannedWorkoutProposal(date: day(dayOffset), definition: def, rationale: "r"),
                              source: .manual, weekFocus: nil)
        container.mainContext.insert(w)
        try? container.mainContext.save()
        return w
    }

    /// Schwere Beine, Ende `hours` Stunden vor dem Start der Schlüsseleinheit.
    func addLegDay(_ model: AppModel, endingHoursBefore hours: Double, before key: Date) {
        let end = key.addingTimeInterval(-hours * 3600)
        model.saveStrengthManual(start: end.addingTimeInterval(-3600), durationMinutes: 60, exertion: 8, legShare: .heavy,
                                 exercises: [PerformedExercise(exerciseID: "squat", sets: 4, reps: 6, weightKg: 100)])
    }

    // MARK: Konflikt

    @Test func conflictDetectedWithinTwentyFourHours() throws {
        let (model, container) = try makeModel()
        let key = addWorkout(container, type: .vo2max, title: "VO₂ 5×4", dayOffset: 1)
        addLegDay(model, endingHoursBefore: 20, before: model.startDate(for: key))
        let hint = try #require(model.legLoadHint(for: key))
        #expect(hint.conflict.intensity == .vo2)
        #expect(hint.message.contains("Kniebeuge"))
        #expect(hint.message.contains("Härte 8"))
        #expect(hint.message.contains("Faustregel"))
    }

    @Test func exactlyTwentyFourHoursIsNoConflict() throws {
        let (model, container) = try makeModel()
        let key = addWorkout(container, type: .threshold, title: "Schwelle", dayOffset: 1)
        addLegDay(model, endingHoursBefore: 24, before: model.startDate(for: key))
        #expect(model.legLoadHint(for: key) == nil)
    }

    @Test func noBannerForBaseWorkoutOrLightLegs() throws {
        let (model, container) = try makeModel()
        let base = addWorkout(container, type: .endurance, title: "Grundlage", dayOffset: 1)
        addLegDay(model, endingHoursBefore: 10, before: model.startDate(for: base))
        #expect(model.legLoadHint(for: base) == nil)

        let (model2, container2) = try makeModel()
        let key = addWorkout(container2, type: .anaerobic, title: "Anaerob", dayOffset: 1)
        let end = model2.startDate(for: key).addingTimeInterval(-5 * 3600)
        model2.saveStrengthManual(start: end.addingTimeInterval(-1800), durationMinutes: 30, exertion: 5, legShare: .light, exercises: [])
        #expect(model2.legLoadHint(for: key) == nil)
    }

    @Test func hintNamesNextBaseWorkout() throws {
        let (model, container) = try makeModel()
        let key = addWorkout(container, type: .vo2max, title: "VO₂", dayOffset: 1)
        addWorkout(container, type: .sweetSpot, title: "SS", dayOffset: 2)
        let base = addWorkout(container, type: .endurance, title: "Lockere Grundlage", dayOffset: 3)
        addLegDay(model, endingHoursBefore: 12, before: model.startDate(for: key))
        let hint = try #require(model.legLoadHint(for: key))
        #expect(hint.base?.id == base.id)
        #expect(hint.message.contains("Lockere Grundlage"))
    }

    // MARK: Aktionen

    @Test func swapExchangesDatesOfBothWorkouts() async throws {
        let (model, container) = try makeModel()
        let key = addWorkout(container, type: .vo2max, title: "VO₂", dayOffset: 1)
        let base = addWorkout(container, type: .endurance, title: "Grundlage", dayOffset: 3)
        let keyDate = key.date, baseDate = base.date
        addLegDay(model, endingHoursBefore: 12, before: model.startDate(for: key))
        let hint = try #require(model.legLoadHint(for: key))
        let ok = await model.swapForLegLoad(key, with: try #require(hint.base))
        #expect(ok)
        #expect(key.date == baseDate)
        #expect(base.date == keyDate)
        // Der Konflikt ist weg: die Schlüsseleinheit liegt jetzt später.
        #expect(model.legLoadHint(for: key) == nil)
    }

    @Test func swapRefusesNonPlannedOrSameWorkout() async throws {
        let (model, container) = try makeModel()
        let key = addWorkout(container, type: .vo2max, title: "VO₂", dayOffset: 1)
        let base = addWorkout(container, type: .endurance, title: "G", dayOffset: 3)
        base.status = .done
        #expect(await model.swapForLegLoad(key, with: base) == false)
        #expect(await model.swapForLegLoad(key, with: key) == false)
        #expect(key.date == day(1))
    }

    @Test func keepPersistsAndHidesBanner() throws {
        let suite = "legload-keep-\(UUID().uuidString)"
        let (model, container) = try makeModel(suite: suite)
        let key = addWorkout(container, type: .threshold, title: "Schwelle", dayOffset: 1)
        addLegDay(model, endingHoursBefore: 8, before: model.startDate(for: key))
        #expect(model.legLoadHint(for: key) != nil)
        model.keepLegLoad(key)
        #expect(model.legLoadHint(for: key) == nil)
        // Neues Modell auf denselben Defaults und demselben Store: bleibt ausgeblendet.
        let again = AppModel(context: container.mainContext, secrets: InMemorySecretStore(),
                             defaults: UserDefaults(suiteName: suite)!,
                             transport: RoutingTransport { _ in (200, Data("{}".utf8)) })
        #expect(again.legLoadHint(for: key) == nil)
    }

    @Test func lightenAdjustsByTenPercentAndHides() async throws {
        let (model, container) = try makeModel()
        let key = addWorkout(container, type: .vo2max, title: "VO₂", dayOffset: 1)
        addLegDay(model, endingHoursBefore: 8, before: model.startDate(for: key))
        await model.lightenForLegLoad(key)
        #expect(key.adjustmentNote != nil)
        #expect(model.legLoadHint(for: key) == nil)
    }

    // MARK: Plan-Kontext

    @Test func planContextCarriesStrengthAndStudioDays() throws {
        let (model, _) = try makeModel()
        let now = noon
        model.saveStrengthManual(start: now.addingTimeInterval(-26 * 3600), durationMinutes: 60, exertion: 8, legShare: .heavy, exercises: [])
        model.saveStrengthManual(start: now.addingTimeInterval(-10 * 86400), durationMinutes: 60, exertion: 5, legShare: .light, exercises: [])
        let target = day(2)
        model.strengthDays = [cal.component(.weekday, from: target)]
        let ctx = model.planContext(wish: "", startToday: false, now: now)
        let s = try #require(ctx.strength)
        #expect(s.sessions.count == 1)                 // nur die letzten 7 Tage
        #expect(s.sessions[0].legs == .heavy)
        #expect(s.sessions[0].exertion == 8)
        #expect(s.sessions[0].minutes == 60)
        #expect(s.studioDays.contains(target))
        #expect(s.studioDays.allSatisfy { $0 >= ctx.horizonStart && $0 <= ctx.horizonEnd })
    }

    @Test func planContextWithoutStrengthDataIsNil() throws {
        let (model, _) = try makeModel()
        let ctx = model.planContext(wish: "", startToday: true)
        #expect(ctx.strength == nil)
        #expect(ctx.otherSports.isEmpty)
    }

    @Test func otherSportsOnlyAerobicLastFourteenDays() {
        let now = noon
        func ride(_ id: Int, _ sport: String, daysAgo: Int) -> RideSummary {
            RideSummary(id: id, name: "Name\(id)", sportType: sport, startDate: now.addingTimeInterval(-Double(daysAgo) * 86400),
                        movingTime: 3000, distance: 8000, averageHeartrate: 150, maxHeartrate: 175)
        }
        let rides = [ride(1, "Run", daysAgo: 2), ride(2, "Run", daysAgo: 20), ride(3, "VirtualRide", daysAgo: 1),
                     ride(4, "WeightTraining", daysAgo: 1), ride(5, "Swim", daysAgo: 5)]
        let list = OtherSportSummary.summaries(from: rides, ftp: 250, thresholdHeartRate: 170,
                                               today: cal.startOfDay(for: now), calendar: cal)
        #expect(list.count == 2)
        #expect(Set(list.map(\.sport)) == ["Laufen", "Schwimmen"])
        #expect(list.allSatisfy { $0.minutes == 50 })
        #expect(list.allSatisfy { $0.estimatedTSS > 0 })
    }

    // MARK: Prompt

    func baseContext() -> PlanContext {
        let today = cal.startOfDay(for: Formatters.isoDay.date(from: "2026-11-16")!)
        return PlanContext(profile: AthleteProfile(), today: today,
                           horizonStart: today, horizonEnd: cal.date(byAdding: .day, value: 6, to: today)!,
                           load: nil, weeks: [], recentRides: [], alreadyPlanned: [], wish: "")
    }

    @Test func promptOmitsSectionWithoutData() {
        #expect(!PlanPrompt.userMessage(baseContext()).contains("Kraft & andere Sportarten"))
    }

    @Test func promptListsStrengthStudioDaysAndOtherSports() {
        var ctx = baseContext()
        let d = ctx.today
        ctx.strength = StrengthWeekSummary(
            sessions: [.init(date: d.addingTimeInterval(-86400), exertion: 8, minutes: 60, legs: .heavy)],
            studioDays: [cal.date(byAdding: .day, value: 2, to: d)!])
        ctx.otherSports = [OtherSportSummary(date: d.addingTimeInterval(-2 * 86400), sport: "Laufen", minutes: 50, estimatedTSS: 55)]
        let msg = PlanPrompt.userMessage(ctx)
        #expect(msg.contains("## Kraft & andere Sportarten"))
        #expect(msg.contains("Härte 8 × 60 min"))
        #expect(msg.contains("Beine schwer"))
        #expect(msg.contains("Studio-Tage"))
        #expect(msg.contains("2026-11-18"))
        #expect(msg.contains("Laufen"))
        #expect(msg.contains("TSS 55"))
    }

    @Test func promptShowsMissingExertionAsUnknown() {
        var ctx = baseContext()
        ctx.strength = StrengthWeekSummary(sessions: [.init(date: ctx.today, exertion: nil, minutes: 40, legs: .light)], studioDays: [])
        let msg = PlanPrompt.userMessage(ctx)
        #expect(msg.contains("Härte unbekannt"))
        #expect(!msg.contains("Studio-Tage"))
    }

    @Test func systemPromptCarriesLegRulesAsRulesOfThumb() {
        let s = PlanPrompt.system
        #expect(s.contains("Faustregel"))
        #expect(s.contains("24 Stunden"))
        #expect(s.contains("3 Stunden"))
        #expect(s.contains("Studio"))
        #expect(s.contains("Wochenlast"))
    }
}
