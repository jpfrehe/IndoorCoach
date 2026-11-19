import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

/// W-F: Erholungswerte, Morgen-HRV, Trend-Wächter, Einwilligung und Löschen sind verbunden.
@Suite("Integration Welle 4 (W-F)", .serialized)
@MainActor
struct IntegrationW4FTests {
    static var keepAlive: [ModelContainer] = []
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let watch = HealthSourceRef(name: "Apple Watch", bundleID: "com.apple.health.watch")
    let garmin = HealthSourceRef(name: "Garmin Connect", bundleID: "com.garmin.connect")

    func makeModel(source: StubHealthDataSource? = nil) throws -> (AppModel, UserDefaults, URL) {
        let container = try AppEnvironment.makeContainer(inMemory: true)
        Self.keepAlive.append(container)
        let defaults = UserDefaults(suiteName: "w4f-\(UUID().uuidString)")!
        AppModel.recoveryWellnessProvider = nil
        AppModel.morningHRVSignalProvider = nil
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults,
                             transport: RoutingTransport { _ in (200, Data("{}".utf8)) })
        model.resetWellnessState()   // der Cache ist über die Objekt-ID verschlüsselt; ein freigegebenes Modell kann Reste hinterlassen
        if let source { model.healthSource = source }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("w4f-hrv-\(UUID().uuidString).json")
        model.morningHRVStoreURL = url
        return (model, defaults, url)
    }

    func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("w4f-\(UUID().uuidString)", isDirectory: true)
    }

    func series(_ values: [Double], _ metric: HealthMetric = .restingHR, source: HealthSourceRef? = nil) -> [HealthDaily] {
        let today = Calendar.current.startOfDay(for: now)
        return values.enumerated().map { i, v in
            HealthDaily(date: Calendar.current.date(byAdding: .day, value: i - (values.count - 1), to: today)!, metric: metric,
                        value: v, source: source ?? watch)
        }
    }

    var risingRHR: [Double] { Array(repeating: 50, count: 25) + [58, 58, 58] }

    func morning(recent: Double, in store: MorningHRVStore) {
        let cal = Calendar.current
        func m(_ ago: Int, _ ln: Double) -> MorningHRV.Measurement {
            let day = cal.startOfDay(for: cal.date(byAdding: .day, value: -ago, to: now)!)
            return .init(day: day, lnRMSSD: ln, beats: 70, quality: 1, measuredAt: day.addingTimeInterval(7 * 3600))
        }
        let base = (7...27).map { m($0, 3.5 + ($0 % 2 == 0 ? 0.1 : -0.1)) }
        for x in base + [0, 1, 3].map({ m($0, recent) }) { store.save(x, now: now) }
        store.enabled = true
    }

    // MARK: 1 Pins

    @Test func pinViaDataSourcesAPIFiltersWellness() async throws {
        let mixed = series(Array(repeating: 50, count: 28)) + series(Array(repeating: 70, count: 28), source: garmin)
        let (model, _, _) = try makeModel(source: StubHealthDataSource(daily: mixed))
        model.healthEnabled = true
        model.pin(garmin, for: .restingHR)
        await model.refreshWellness(now: now, directory: tempDir())
        let trend = model.wellnessTrend(.restingHR, now: now)
        #expect(trend.source == garmin && trend.baseline == 70)
    }

    // MARK: 3 Provider

    @Test func recoverySummaryHasWellnessLinesOnlyWithConsentAndData() async throws {
        let sleep = series(Array(repeating: 7.5, count: 21) + Array(repeating: 6.0, count: 7), .sleepHours)
        let (model, _, _) = try makeModel(source: StubHealthDataSource(daily: sleep + series(Array(repeating: 50, count: 28))))
        #expect(model.planContext(wish: "", startToday: true, now: now).recovery == nil)   // Health aus
        model.healthEnabled = true
        await model.refreshWellness(now: now, directory: tempDir())
        #expect(model.planContext(wish: "", startToday: true, now: now).recovery == nil)   // ohne Einwilligung
        #expect(model.recoverySummary(now: now)?.sleepDeltaHours == -1.5)
        #expect(model.recoverySummary(now: now)?.restingHRDeltaBpm == 0)
        model.grantClaudeConsent(now: now)
        #expect(model.planContext(wish: "", startToday: true, now: now).recovery?.sleepDeltaHours == -1.5)
    }

    @Test func noWellnessWithoutHealthData() throws {
        let (model, _, _) = try makeModel()
        model.healthEnabled = true
        #expect(model.recoverySummary(now: now) == nil)
    }

    @Test func guardUsesMorningHRVAsSecondSignal() async throws {
        let (model, defaults, url) = try makeModel(source: StubHealthDataSource(daily: series(risingRHR)))
        model.healthEnabled = true
        await model.refreshWellness(now: now, directory: tempDir())
        #expect(model.trendGuardResult(now: now) == .quiet)
        morning(recent: 3.0, in: MorningHRVStore(url: url, defaults: defaults))
        #expect(model.trendGuardResult(now: now) == .triggered(variant: .restingHR, reasons: [.restingHR, .morningHRV]))
        #expect(model.recoverySummary(now: now)?.trendGuardActive == true)
    }

    // MARK: 2 Löschen

    @Test func deleteAllDataClearsWellnessMorningHRVAndConsent() async throws {
        let (model, defaults, url) = try makeModel(source: StubHealthDataSource(daily: series(risingRHR)))
        model.healthEnabled = true
        let dir = tempDir()
        await model.refreshWellness(now: now, directory: dir)
        let cache = dir.appendingPathComponent(AppModel.wellnessCacheFile)
        #expect(FileManager.default.fileExists(atPath: cache.path))
        morning(recent: 3.0, in: MorningHRVStore(url: url, defaults: defaults))
        #expect(FileManager.default.fileExists(atPath: url.path))
        model.trendGuardShadowMode = true
        model.grantClaudeConsent(now: now)

        await model.deleteAllData()

        #expect(!FileManager.default.fileExists(atPath: cache.path))
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(model.claudeConsent == nil)
        #expect(!model.trendGuardShadowMode)
        #expect(!MorningHRVStore(url: url, defaults: defaults).enabled)
    }
}
