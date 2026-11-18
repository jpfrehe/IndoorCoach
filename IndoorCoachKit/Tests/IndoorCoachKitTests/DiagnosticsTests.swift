import Foundation
import OSLog
import SwiftData
import Testing
@testable import IndoorCoachKit

@Suite("Diagnose & Redaktion")
@MainActor
struct DiagnosticsTests {
    nonisolated static let claudeKey = "sk-ant-api03-SECRETKEY_abc-1234567890"
    nonisolated static let clientSecret = "f00dbabe11223344556677889900aabbccddeeff"
    nonisolated static let accessToken = "0123456789abcdef0123456789abcdef01234567"
    nonisolated static let refreshToken = "fedcba9876543210fedcba9876543210fedcba98"

    /// Model with stored secrets, a connected Strava account, personal free text and one demo ride.
    func makeModel() throws -> (ModelContainer, AppModel) {
        let container = try AppEnvironment.makeContainer(inMemory: true)
        let secrets = InMemorySecretStore()
        secrets.setSecret(Self.claudeKey, for: .claudeAPIKey)
        secrets.setSecret(Self.clientSecret, for: .stravaClientSecret)
        secrets.saveTokens(StravaTokens(accessToken: Self.accessToken, refreshToken: Self.refreshToken,
                                        expiresAt: .now.addingTimeInterval(3600), athleteName: "Erika Mustermann"))
        let defaults = UserDefaults(suiteName: "diag-\(UUID().uuidString)")!
        let model = AppModel(context: container.mainContext, secrets: secrets, defaults: defaults)
        model.profile.goal = "Ötztaler unter 9 Stunden"
        model.profile.notes = "Knie links schonen"
        model.stravaClientID = "123456"
        let ride = DemoData.rides(days: 7, ftp: 250).first!
        container.mainContext.insert(StoredRide(ride, isDemo: true))
        try container.mainContext.save()
        return (container, model)
    }

    nonisolated static let leakyLines = [
        "2026-11-17T08:00:00Z [claude] error: invalid x-api-key \(claudeKey) provided",
        "2026-11-17T08:00:01Z [strava] notice: Authorization: Bearer \(accessToken)",
        "2026-11-17T08:00:02Z [strava] notice: POST body client_id=123456&client_secret=\(clientSecret)&code=9f8e7d6c5b4a",
        "2026-11-17T08:00:03Z [strava] notice: {\"access_token\":\"abc\",\"refresh_token\":\"\(refreshToken)\"}",
        "2026-11-17T08:00:04Z [sync] notice: raw secret \(clientSecret) and Bearer xyz.short-token",
        "2026-11-17T08:00:05Z [sync] notice: Fahrt von Erika Mustermann bei 47.123456, 11.987654 – Ziel Ötztaler unter 9 Stunden, Knie links schonen",
        "2026-11-17T08:00:06Z [sync] notice: Sync beendet: 12 Fahrten geladen, 3 neu"
    ]

    @Test func reportRedactsSecretsEvenIfLogged() async throws {
        let (container, model) = try makeModel()
        defer { withExtendedLifetime(container) {} }
        let report = await model.diagnosticsReport(since: .now.addingTimeInterval(-86_400)) { _ in Self.leakyLines }
        #expect(!report.contains(Self.claudeKey))
        #expect(report.range(of: #"sk-ant-[A-Za-z0-9_\-]{3,}"#, options: .regularExpression) == nil)
        #expect(report.range(of: #"(?i)bearer\s+[A-Za-z0-9]"#, options: .regularExpression) == nil)
        #expect(!report.contains(Self.clientSecret))
        #expect(!report.contains(Self.accessToken))
        #expect(!report.contains(Self.refreshToken))
        #expect(!report.contains("9f8e7d6c5b4a"))
        #expect(!report.contains("Erika"))
        #expect(!report.contains("47.123456"))
        #expect(!report.contains("Ötztaler"))
        #expect(!report.contains("Knie"))
        // Harmless diagnostics survive.
        #expect(report.contains("Sync beendet: 12 Fahrten geladen, 3 neu"))
    }

    @Test func reportContainsHeaderFields() async throws {
        let (container, model) = try makeModel()
        defer { withExtendedLifetime(container) {} }
        let report = await model.diagnosticsReport(since: .now.addingTimeInterval(-86_400)) { _ in [] }
        for field in ["App-Version:", "Betriebssystem:", "Gerät:", "FTP: 250 W", "Trainingstage:",
                      "Fahrten: 1 (Strava 0, Demo 1)", "Einheiten: 0", "Strava verbunden: ja",
                      "Claude-Key hinterlegt: ja", "== Protokoll ==", "(keine Einträge)",
                      "Mac-Brücke gekoppelt: nein", "Fahrten mit Sekundendaten: 0 von 1"] {
            #expect(report.contains(field), "fehlt: \(field)")
        }
    }

    /// The Mac's name is personal ("Lenas MacBook Air") and must not appear in the export.
    @Test func reportShowsBridgeStateWithoutTheMacName() async throws {
        let (container, model) = try makeModel()
        defer { withExtendedLifetime(container) {} }
        model.bridge.macName = "Lenas MacBook Air"
        model.secrets.setSecret(Data(count: 32).base64EncodedString(), for: .bridgeSecret)
        let report = await model.diagnosticsReport(since: .now.addingTimeInterval(-86_400)) { _ in ["paired with Lenas MacBook Air"] }
        #expect(report.contains("Mac-Brücke gekoppelt: ja"))
        #expect(!report.contains("Lenas MacBook Air"))
    }

    @Test func reportHandlesUnavailableLogStore() async throws {
        struct Unavailable: Error {}
        let (container, model) = try makeModel()
        defer { withExtendedLifetime(container) {} }
        let report = await model.diagnosticsReport(since: .now) { _ in throw Unavailable() }
        #expect(report.contains("Protokoll nicht verfügbar"))
        #expect(report.contains("App-Version:"))
    }

    /// End-to-end against the real unified log: even a raw `Logger` call that bypasses the facade
    /// must not leak into the export.
    @Test func realLogStoreExportIsRedacted() async throws {
        let (container, model) = try makeModel()
        defer { withExtendedLifetime(container) {} }
        Log.notice(.claude, "facade key \(Self.claudeKey)")
        Logger(subsystem: Log.subsystem, category: "test")
            .notice("raw \(Self.claudeKey, privacy: .public) Bearer \(Self.accessToken, privacy: .public)")
        let report = await model.diagnosticsReport()
        #expect(report.contains("App-Version:"))
        #expect(!report.contains(Self.claudeKey))
        #expect(!report.contains(Self.accessToken))
    }

    @Test func redactorPatterns() {
        #expect(Redactor.scrub("key sk-ant-api03-ABC_def-123 x") == "key sk-ant-… x")
        #expect(Redactor.scrub("Authorization: Bearer abc.def-123") == "Authorization: Bearer …")
        #expect(Redactor.scrub("client_secret=s3cr%26t&grant_type=x") == "client_secret=…&grant_type=x")
        #expect(Redactor.scrub(#""code": "XYZ123""#) == #""code": "…""#)
        #expect(Redactor.scrub("HTTP 429 /api/v3/athlete/activities") == "HTTP 429 /api/v3/athlete/activities")
        #expect(Redactor.scrub("Tokens: input 1200, output 3400") == "Tokens: input 1200, output 3400")
        #expect(Redactor.scrub("hello world", knownSecrets: ["world"]) == "hello world") // too short to be a secret
        #expect(Redactor.scrub("my secret-value!", knownSecrets: ["secret-value"]) == "my ‹entfernt›!")
    }

    @Test func feedbackMailURL() {
        #expect(AppConfig.feedbackMailURL(email: "", subject: "s", body: "b") == nil)
        let url = AppConfig.feedbackMailURL(email: "pilot@example.org", subject: "IndoorCoach Feedback", body: "Hallo Welt")
        #expect(url?.scheme == "mailto")
        #expect(url?.absoluteString.hasPrefix("mailto:pilot@example.org?subject=IndoorCoach%20Feedback") == true)
    }
}
