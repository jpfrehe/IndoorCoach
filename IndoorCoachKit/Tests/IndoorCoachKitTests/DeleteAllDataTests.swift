import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

/// B02 "Alle Daten löschen". The calendar part is a no-op here: the test process never has calendar access.
@MainActor
@Suite("Alle Daten löschen")
struct DeleteAllDataTests {
    @Test func deleteAllDataEmptiesStoreSecretsAndDefaults() async throws {
        let container = try AppEnvironment.makeContainer(inMemory: true)
        let suite = "delete-all-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let secrets = InMemorySecretStore()
        let model = AppModel(context: container.mainContext, secrets: secrets, defaults: defaults)

        // Fill everything the app persists.
        model.bootstrap()
        model.profile.ftp = 300
        model.profile.goal = "FTP 320"
        model.stravaClientID = "123456"
        defaults.set(Date.now, forKey: AppModel.Keys.lastSync)
        defaults.set(true, forKey: AppModel.Keys.ridesImported)
        defaults.set(Date.now, forKey: AppModel.Keys.myWhooshLastImport)
        defaults.set(Date.now, forKey: AppModel.Keys.intervalsLastImport)
        defaults.set("Jan", forKey: AppModel.Keys.intervalsAthleteName)
        defaults.set(["i7"], forKey: AppModel.Keys.intervalsUnreadable)
        SecretIntervalsCredentialStore(secrets: secrets).saveCredential(.apiKey("key-123456"))
        model.syncErrors[.intervalsICU] = "Zugang abgelaufen – bitte neu verbinden."
        defaults.set(["2026-11-16"], forKey: AppModel.Keys.weeklyReviewDismissed)
        secrets.setSecret("c2VjcmV0", for: .bridgeSecret)
        defaults.set("Lenas MacBook Air", forKey: AppModel.Keys.bridgeMacName)
        defaults.set(Date.now, forKey: AppModel.Keys.bridgeLastSync)
        defaults.set(["fit-1"], forKey: AppModel.Keys.bridgeKnownIDs)
        defaults.set(Data([1]), forKey: AppModel.Keys.recordingPending)  // ANCHOR-REC
        defaults.set(Data([1]), forKey: AppModel.Keys.recordingAttached)
        // Welle 3: Kraft-Vorlagen und Studio-Tage, Joker, Beinlast-Hinweis, Gurt, Health-Export.
        model.saveStrengthTemplate(StrengthTemplate(name: "Push", exerciseIDs: ["squat"]))
        model.strengthDays = [2, 4]
        defaults.set([1_800_000_000.0], forKey: AppModel.Keys.manualJokerWeeks)
        defaults.set(["w"], forKey: AppModel.Keys.legLoadKept)
        StrapStore(defaults: defaults).savedID = UUID()
        model.healthWriter = StubHealthWorkoutWriter()
        try await model.healthExport.setEnabled(.strength, true)
        defaults.set(["e"], forKey: AppModel.Keys.healthExportLedger)
        model.setPlanFeedback(.up, forWeek: .now) // B33: Plan-Feedback je Woche
        model.bridge.load(defaults: defaults)
        model.onboardingStep = 2
        model.onboardingServices = OnboardingServicesState(answers: ServiceAnswers(rideApps: [.zwift], extras: [.heartStrap]),
                                                           deferred: [.strap], stravaAfterwards: true)   // Einführung v3
        model.syncErrors[.strava] = "Synchronisierung fehlgeschlagen"
        model.setClaudeAPIKey("placeholder-claude-key")
        model.setStravaClientSecret("client-secret")
        secrets.saveTokens(StravaTokens(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture, athleteName: "Test"))
        model.refreshCredentialState()
        #expect(model.isIntervalsConnected && model.intervalsAthleteName == "Jan")
        let context = container.mainContext
        #expect(try context.fetchCount(FetchDescriptor<StoredRide>()) > 0)
        #expect(try context.fetchCount(FetchDescriptor<StoredWorkout>()) > 0)
        #expect(model.isStravaConnected && model.hasClaudeKey && model.hasStravaSecret)
        for key in AppModel.Keys.all { #expect(defaults.object(forKey: key) != nil, "\(key) not set up") }

        await model.deleteAllData()

        #expect(try context.fetchCount(FetchDescriptor<StoredRide>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<StoredWorkout>()) == 0)
        #expect(secrets.secret(.claudeAPIKey) == nil)
        #expect(secrets.secret(.stravaClientSecret) == nil)
        #expect(secrets.secret(.bridgeSecret) == nil)
        #expect(model.bridgeMacName == nil && model.lastBridgeSync == nil && !model.isBridgePaired)
        #expect(secrets.loadTokens() == nil)
        #expect(secrets.secret(.intervalsCredential) == nil)
        #expect(!model.isIntervalsConnected && model.intervalsAthleteName == nil && model.lastIntervalsImport == nil)
        for key in AppModel.Keys.all { #expect(defaults.object(forKey: key) == nil, "\(key) still set") }
        #expect(defaults.persistentDomain(forName: suite)?.isEmpty ?? true)
        #expect(model.profile == AthleteProfile())
        #expect(model.stravaClientID.isEmpty && model.lastSync == nil)
        #expect(!model.isStravaConnected && !model.hasClaudeKey && !model.hasStravaSecret)
        #expect(model.syncErrors.isEmpty)
        #expect(model.onboardingServices == OnboardingServicesState() && model.onboardingStep == 0)
        #expect(model.banner?.message == "Alle Daten gelöscht.")
        #expect(model.banner?.isError == false)
    }

    @Test func freshModelAfterDeletionStartsWithDefaults() async throws {
        let container = try AppEnvironment.makeContainer(inMemory: true)
        let suite = "delete-all-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults)
        model.profile.ftp = 333
        await model.deleteAllData()

        let reopened = AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults)
        #expect(reopened.profile == AthleteProfile())
    }

    @Test func deleteAllDataRemovesCheckIns() async throws {
        let container = try AppEnvironment.makeContainer(inMemory: true)
        let suite = "delete-all-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults)
        container.mainContext.insert(StoredCheckIn(day: Calendar.current.startOfDay(for: .now), answers: CheckIn.Answers(), offered: []))
        try container.mainContext.save()
        #expect(try container.mainContext.fetchCount(FetchDescriptor<StoredCheckIn>()) == 1)
        await model.deleteAllData()
        #expect(try container.mainContext.fetchCount(FetchDescriptor<StoredCheckIn>()) == 0)
    }

    @Test func deleteAllDataStopsRunningServices() async throws {
        let container = try AppEnvironment.makeContainer(inMemory: true)
        let suite = "delete-all-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults)
        let store = RecordingStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("del-\(UUID().uuidString)"))
        let presenter = NoopRecordingLivePresenter()
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let recorder = RecordingService(strap: nil, now: { clock.date }, store: store, presenter: { presenter }, autoTick: false)
        let controller = StubStrapController(autoplay: false)
        let strap = StrapSession(controller: controller)
        model.recordingServiceOverride = recorder
        model.strapSessionOverride = strap
        recorder.start(kind: .ride, title: "Läuft")
        clock.advance(40); recorder.tick()                      // Zwischendatei liegt vor
        #expect(recorder.isRunning && store.load() != nil)
        let export = Task<Void, Never> { try? await Task.sleep(for: .seconds(60)) }
        model.healthExportTask = export
        // Wartende Aufzeichnung (Datei) muss ebenfalls fallen.
        _ = model.finishRecording(RecordingResult(kind: .ride, title: "x", startedAt: clock.date.addingTimeInterval(-600), endedAt: clock.date,
                                                  seconds: RideSeconds(power: [UInt16](repeating: 0, count: 600), heartRate: [UInt8](repeating: 120, count: 600))))
        #expect(model.pendingRecordings.count == 1)

        await model.deleteAllData()

        #expect(!recorder.isRunning)                             // abgebrochen, ohne zu speichern
        #expect(store.load() == nil)
        #expect(!presenter.isActive)
        #expect(controller.forgotten)                            // Gurt getrennt und vergessen
        #expect(export.isCancelled)
        #expect(model.pendingRecordings.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: model.pendingRecordingsURL.path))
    }
}
