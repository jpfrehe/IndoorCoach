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
