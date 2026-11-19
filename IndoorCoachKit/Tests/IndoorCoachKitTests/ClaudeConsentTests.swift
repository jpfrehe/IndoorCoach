import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

@Suite("Claude-Einwilligung (W4-C)", .serialized)
@MainActor
struct ClaudeConsentTests {
    static var keepAlive: [ModelContainer] = []
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func makeModel() throws -> AppModel {
        let container = try AppEnvironment.makeContainer(inMemory: true)
        Self.keepAlive.append(container)
        let defaults = UserDefaults(suiteName: "w4c-\(UUID().uuidString)")!
        AppModel.recoveryWellnessProvider = nil
        return AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults,
                        transport: RoutingTransport { _ in (200, Data("{}".utf8)) })
    }

    func addCheckIn(_ model: AppModel, daysAgo: Int, legs: CheckIn.Level = .bad) {
        let day = Calendar.current.startOfDay(for: now.addingTimeInterval(-Double(daysAgo) * 86_400))
        model.context.insert(StoredCheckIn(day: day, answers: CheckIn.Answers(legs: legs), offered: [], createdAt: day))
        try? model.context.save()
    }

    struct FakeProvider: RecoveryWellnessProviding {
        func recoveryWellness(today: Date) -> RecoveryWellness? {
            RecoveryWellness(sleepRecentHours: 6.5, sleepBaselineHours: 7.5)
        }
    }

    @Test func ohneEinwilligungKeinRecovery() throws {
        let model = try makeModel()
        addCheckIn(model, daysAgo: 1)
        #expect(model.claudeConsent == nil)
        #expect(model.planContext(wish: "", startToday: true, now: now).recovery == nil)
    }

    @Test func mitEinwilligungRecoveryGesetzt() throws {
        let model = try makeModel()
        addCheckIn(model, daysAgo: 1)
        addCheckIn(model, daysAgo: 3)
        model.grantClaudeConsent(now: now)
        let r = model.planContext(wish: "", startToday: true, now: now).recovery
        #expect(r?.checkIns.legsHeavy == 2)
    }

    @Test func widerrufEntferntRecoveryWieder() throws {
        let model = try makeModel()
        addCheckIn(model, daysAgo: 1)
        model.grantClaudeConsent(now: now)
        model.revokeClaudeConsent()
        #expect(model.claudeConsent == nil)
        #expect(model.planContext(wish: "", startToday: true, now: now).recovery == nil)
    }

    @Test func zustandHatDatumUndVersion() throws {
        let model = try makeModel()
        model.grantClaudeConsent(now: now)
        #expect(model.claudeConsent?.grantedAt == now)
        #expect(model.claudeConsent?.version == ClaudeConsent.currentVersion)
    }

    @Test func alteVersionGiltNichtMehr() throws {
        let model = try makeModel()
        let old = ClaudeConsent(grantedAt: now, version: ClaudeConsent.currentVersion - 1)
        model.defaults.set(try JSONEncoder().encode(old), forKey: AppModel.ConsentKeys.consent)
        #expect(model.claudeConsent == nil)
    }

    @Test func checkInsAelterAls14TageZaehlenNicht() throws {
        let model = try makeModel()
        addCheckIn(model, daysAgo: 20)
        model.grantClaudeConsent(now: now)
        #expect(model.planContext(wish: "", startToday: true, now: now).recovery == nil)
    }

    @Test func abfrageNurBeiDatenUndOhneEntscheidung() throws {
        let model = try makeModel()
        #expect(!model.needsClaudeConsentPrompt(now: now))            // keine Daten
        addCheckIn(model, daysAgo: 1)
        #expect(model.needsClaudeConsentPrompt(now: now))
        model.declineClaudeConsent()
        #expect(!model.needsClaudeConsentPrompt(now: now))            // einmal entschieden
        #expect(model.claudeConsent == nil)
    }

    @Test func abfrageAuchMitProviderDaten() throws {
        let model = try makeModel()
        AppModel.recoveryWellnessProvider = FakeProvider()
        defer { AppModel.recoveryWellnessProvider = nil }
        #expect(model.needsClaudeConsentPrompt(now: now))
        model.grantClaudeConsent(now: now)
        #expect(!model.needsClaudeConsentPrompt(now: now))
        #expect(model.planContext(wish: "", startToday: true, now: now).recovery?.sleepDeltaHours == -1.0)
    }

    @Test func vorschauZeigtEchtenAbschnittAuchOhneEinwilligung() throws {
        let model = try makeModel()
        #expect(model.recoveryPreviewText(now: now).contains("nichts"))
        addCheckIn(model, daysAgo: 1)
        #expect(model.recoveryPreviewText(now: now).contains("1× Beine schwer"))
        #expect(model.claudeConsent == nil)
    }

    @Test func resetRaeumtAuf() throws {
        let model = try makeModel()
        addCheckIn(model, daysAgo: 1)
        model.grantClaudeConsent(now: now)
        model.resetConsentState()
        #expect(model.claudeConsent == nil)
        #expect(model.needsClaudeConsentPrompt(now: now))   // Entscheidung ebenfalls zurückgesetzt
    }
}
