import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

@Suite("AppModel+Wellness (Erholungswerte und Trend-Wächter)")
@MainActor
struct AppModelWellnessTests {
    static var keepAlive: [ModelContainer] = []

    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let watch = HealthSourceRef(name: "Apple Watch", bundleID: "com.apple.health.watch")
    let garmin = HealthSourceRef(name: "Garmin Connect", bundleID: "com.garmin.connect")

    func definition(_ type: WorkoutType) -> WorkoutDefinition {
        WorkoutDefinition(title: "Test", type: type, summary: "s", segments: [
            .warmup(15, from: 0.45, to: 0.75), .intervals(5, on: 240, at: 1.15, off: 240, at: 0.5), .cooldown(10, from: 0.65, to: 0.4)
        ])
    }

    func makeModel(source: StubHealthDataSource? = nil, suite: String = "wellness-\(UUID().uuidString)",
                   enabled: Bool = true) throws -> (AppModel, UserDefaults, ModelContainer) {
        let container = try AppEnvironment.makeContainer(inMemory: true)
        Self.keepAlive.append(container)
        let defaults = UserDefaults(suiteName: suite)!
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults,
                             transport: RoutingTransport { _ in (200, Data("{}".utf8)) })
        if let source { model.healthSource = source }
        model.healthEnabled = enabled
        return (model, defaults, container)
    }

    func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("wellness-\(UUID().uuidString)", isDirectory: true)
    }

    /// Tageswerte: `values` aufsteigend, der letzte Wert liegt am Tag von `now`.
    func series(_ values: [Double], _ metric: HealthMetric = .restingHR, source: HealthSourceRef? = nil) -> [HealthDaily] {
        let today = Calendar.current.startOfDay(for: now)
        return values.enumerated().map { i, v in
            HealthDaily(date: Calendar.current.date(byAdding: .day, value: i - (values.count - 1), to: today)!, metric: metric,
                        value: v, source: source ?? watch)
        }
    }

    var risingRHR: [Double] { Array(repeating: 50, count: 25) + [58, 58, 58] }

    func plan(_ type: WorkoutType, in container: ModelContainer, daysAhead: Int = 0) {
        let date = Calendar.current.date(byAdding: .day, value: daysAhead, to: now)!
        container.mainContext.insert(StoredWorkout(proposal: PlannedWorkoutProposal(date: date, definition: definition(type), rationale: "r"),
                                                   source: .manual, weekFocus: nil))
    }

    // MARK: Laden und Cache

    @Test func doesNothingWithoutHealthEnabled() async throws {
        let dir = tempDir()
        let (model, _, _) = try makeModel(source: StubHealthDataSource(daily: series(Array(repeating: 50, count: 28))), enabled: false)
        await model.refreshWellness(now: now, directory: dir)
        #expect(!model.wellnessTrend(.restingHR, now: now).isReady)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func loadsTrendAndCachesLocally() async throws {
        let dir = tempDir()
        let (model, _, _) = try makeModel(source: StubHealthDataSource(daily: series(Array(repeating: 50, count: 28))))
        await model.refreshWellness(now: now, directory: dir)
        let trend = model.wellnessTrend(.restingHR, now: now)
        #expect(trend.isReady && trend.baseline == 50 && trend.source == watch)
        #expect(!model.wellnessTrend(.sleepHours, now: now).isReady)

        // Neues Modell, Health nicht verfügbar: der Cache trägt den Trend.
        let (second, _, _) = try makeModel(source: StubHealthDataSource(isAvailable: false))
        await second.refreshWellness(now: now, directory: dir)
        #expect(second.wellnessTrend(.restingHR, now: now).baseline == 50)
    }

    @Test func pinnedSourceWins() async throws {
        let mixed = series(Array(repeating: 50, count: 28)) + series(Array(repeating: 70, count: 28), source: garmin)
        let (model, defaults, _) = try makeModel(source: StubHealthDataSource(daily: mixed))
        var pins = HealthSourcePins()
        pins.pin(garmin, for: .restingHR, from: nil)
        defaults.set(try JSONEncoder().encode(pins), forKey: AppModel.wellnessPinsKey)
        await model.refreshWellness(now: now, directory: tempDir())
        let trend = model.wellnessTrend(.restingHR, now: now)
        #expect(trend.source == garmin && trend.baseline == 70)
    }

    @Test func disablingHealthHidesTrends() async throws {
        let (model, _, _) = try makeModel(source: StubHealthDataSource(daily: series(Array(repeating: 50, count: 28))))
        await model.refreshWellness(now: now, directory: tempDir())
        model.healthEnabled = false
        #expect(!model.wellnessTrend(.restingHR, now: now).isReady)
        #expect(model.trendGuardResult(now: now) == .quiet)
    }

    // MARK: Wächter

    @Test func guardNeedsSecondSignalFromCheckIn() async throws {
        let (model, _, container) = try makeModel(source: StubHealthDataSource(daily: series(risingRHR)))
        plan(.vo2max, in: container)
        await model.refreshWellness(now: now, directory: tempDir())
        #expect(model.trendGuardResult(now: now) == .quiet)
        model.saveCheckIn(CheckIn.Answers(legs: .bad, sleep: .bad, mood: .ok), jokersAvailable: 1, now: now)
        #expect(model.trendGuardResult(now: now) == .triggered(variant: .restingHR, reasons: [.restingHR, .negativeCheckIn]))
    }

    @Test func infectionTagCountsAndMorningHRVClosureIsUsed() async throws {
        let (model, _, container) = try makeModel(source: StubHealthDataSource(daily: series(risingRHR)))
        plan(.vo2max, in: container)
        await model.refreshWellness(now: now, directory: tempDir())
        #expect(model.trendGuardResult(now: now, morningHRVSignal: { true }) == .triggered(variant: .restingHR, reasons: [.restingHR, .morningHRV]))
        #expect(model.trendGuardResult(now: now, morningHRVSignal: { nil }) == .quiet)
        model.saveCheckIn(CheckIn.Answers(tags: [.infekt]), jokersAvailable: 0, now: now)
        #expect(model.trendGuardResult(now: now).reasons == [.restingHR, .infectionTag])
    }

    @Test func oldCheckInsDoNotCount() async throws {
        let (model, _, container) = try makeModel(source: StubHealthDataSource(daily: series(risingRHR)))
        await model.refreshWellness(now: now, directory: tempDir())
        let old = Calendar.current.date(byAdding: .day, value: -5, to: now)!
        container.mainContext.insert(StoredCheckIn(day: Calendar.current.startOfDay(for: old),
                                                   answers: CheckIn.Answers(legs: .bad, sleep: .bad), offered: [], createdAt: old))
        #expect(model.trendGuardResult(now: now) == .quiet)
    }

    // MARK: Karte, Schattenmodus

    @Test func hintOnlyBeforeHardWorkout() async throws {
        let (model, _, container) = try makeModel(source: StubHealthDataSource(daily: series(risingRHR)))
        plan(.endurance, in: container)
        await model.refreshWellness(now: now, directory: tempDir())
        model.saveCheckIn(CheckIn.Answers(legs: .bad, sleep: .bad), jokersAvailable: 1, now: now)
        #expect(model.trendGuardResult(now: now).isTriggered)
        #expect(model.trendHint(now: now) == nil)
    }

    @Test func hintShowsWithOffersAndCanBeDismissed() async throws {
        let (model, _, container) = try makeModel(source: StubHealthDataSource(daily: series(risingRHR)))
        plan(.threshold, in: container, daysAhead: 1)
        await model.refreshWellness(now: now, directory: tempDir())
        container.mainContext.insert(StoredCheckIn(day: Calendar.current.startOfDay(for: now),
                                                   answers: CheckIn.Answers(legs: .bad, sleep: .bad), offered: [], createdAt: now))
        let hint = try #require(model.trendHint(now: now))
        #expect(hint.result.isTriggered)
        #expect(hint.offers.contains(.swapToBase))
        model.dismissTrendHint(now: now)
        #expect(model.trendHint(now: now) == nil)
    }

    @Test func hintIgnoresWorkoutsFarAway() async throws {
        let (model, _, container) = try makeModel(source: StubHealthDataSource(daily: series(risingRHR)))
        plan(.vo2max, in: container, daysAhead: 5)
        await model.refreshWellness(now: now, directory: tempDir())
        model.saveCheckIn(CheckIn.Answers(legs: .bad, sleep: .bad), jokersAvailable: 1, now: now)
        #expect(model.trendHint(now: now) == nil)
    }

    @Test func shadowModeCountsOncePerDayAndShowsNoCard() async throws {
        let (model, _, container) = try makeModel(source: StubHealthDataSource(daily: series(risingRHR)))
        #expect(!model.trendGuardShadowMode)
        model.trendGuardShadowMode = true
        plan(.vo2max, in: container)
        model.saveCheckIn(CheckIn.Answers(legs: .bad, sleep: .bad), jokersAvailable: 1, now: now)
        await model.refreshWellness(now: now, directory: tempDir())
        await model.refreshWellness(now: now, directory: tempDir())
        #expect(model.trendHint(now: now) == nil)
        #expect(model.trendGuardShadowStats.hits == 1)
        #expect(model.trendGuardShadowStats.days == 1)
    }

    @Test func shadowOffCountsNothing() async throws {
        let (model, _, container) = try makeModel(source: StubHealthDataSource(daily: series(risingRHR)))
        plan(.vo2max, in: container)
        model.saveCheckIn(CheckIn.Answers(legs: .bad, sleep: .bad), jokersAvailable: 1, now: now)
        await model.refreshWellness(now: now, directory: tempDir())
        #expect(model.trendGuardShadowStats.hits == 0)
        #expect(model.trendHint(now: now) != nil)
    }

    @Test func diagnosticsShowShadowCounterWithoutValues() async throws {
        let (model, _, container) = try makeModel(source: StubHealthDataSource(daily: series(risingRHR)))
        model.trendGuardShadowMode = true
        plan(.vo2max, in: container)
        model.saveCheckIn(CheckIn.Answers(legs: .bad, sleep: .bad), jokersAvailable: 1, now: now)
        await model.refreshWellness(now: now, directory: tempDir())
        let header = model.diagnosticsHeader(since: now, now: now)
        #expect(header.contains("Trend-Wächter Schattenmodus: an, Treffer: 1"))
        #expect(!header.contains("58"))
    }

    // MARK: Zurücksetzen

    @Test func resetClearsEverything() async throws {
        let dir = tempDir()
        let (model, defaults, _) = try makeModel(source: StubHealthDataSource(daily: series(Array(repeating: 50, count: 28))))
        model.trendGuardShadowMode = true
        await model.refreshWellness(now: now, directory: dir)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent(AppModel.wellnessCacheFile).path))
        model.resetWellnessState()
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(AppModel.wellnessCacheFile).path))
        #expect(!model.wellnessTrend(.restingHR, now: now).isReady)
        #expect(!model.trendGuardShadowMode)
        #expect(model.trendGuardShadowStats.hits == 0)
        #expect(defaults.object(forKey: AppModel.wellnessShadowKey) == nil)
    }
}
