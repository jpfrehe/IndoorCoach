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
        model.setClaudeAPIKey("placeholder-claude-key")
        model.setStravaClientSecret("client-secret")
        secrets.saveTokens(StravaTokens(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture, athleteName: "Test"))
        model.refreshCredentialState()
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
        for key in AppModel.Keys.all { #expect(defaults.object(forKey: key) == nil, "\(key) still set") }
        #expect(defaults.persistentDomain(forName: suite)?.isEmpty ?? true)
        #expect(model.profile == AthleteProfile())
        #expect(model.stravaClientID.isEmpty && model.lastSync == nil)
        #expect(!model.isStravaConnected && !model.hasClaudeKey && !model.hasStravaSecret)
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
}
