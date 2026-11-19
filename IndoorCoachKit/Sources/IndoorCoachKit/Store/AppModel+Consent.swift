import Foundation
import SwiftData

/// Einwilligung des Fahrers, dass ein relativer Erholungskontext an Claude (Anthropic) geht
/// (docs/17 §2.3, §9.1 Prinzip 5; Apple-Richtlinie 5.1.2(i)). Ohne gültige Einwilligung bleibt `PlanContext.recovery` leer.
public struct ClaudeConsent: Codable, Equatable, Sendable {
    /// Erhöhen, wenn sich ändert, was an Claude geht: bestehende Einwilligungen gelten dann nicht mehr.
    public static let currentVersion = 1

    public var grantedAt: Date
    public var version: Int

    public init(grantedAt: Date, version: Int = ClaudeConsent.currentVersion) {
        self.grantedAt = grantedAt
        self.version = version
    }
}

extension AppModel {
    enum ConsentKeys {
        static let consent = "claude.consent.v1"
        static let asked = "claude.consent.asked.v1"
        static let all = [consent, asked]
    }

    /// Das Wellness-Paket (Schlaf, Ruhepuls, HRV, Trend-Wächter) setzt hier seinen Anbieter; `nil` = nur Check-ins und Aufwärm-Check.
    static var recoveryWellnessProvider: (any RecoveryWellnessProviding)?

    /// Länge des Erholungsfensters in Tagen.
    static let recoveryWindowDays = 14

    // MARK: Zustand

    /// Gültige Einwilligung (aktuelle Version), sonst `nil`. Nicht beobachtbar: Views halten eine Kopie und laden nach jeder Aktion neu.
    public var claudeConsent: ClaudeConsent? {
        guard let data = defaults.data(forKey: ConsentKeys.consent),
              let value = try? JSONDecoder().decode(ClaudeConsent.self, from: data),
              value.version == ClaudeConsent.currentVersion else { return nil }
        return value
    }

    public func grantClaudeConsent(now: Date = .now) {
        if let data = try? JSONEncoder().encode(ClaudeConsent(grantedAt: now)) { defaults.set(data, forKey: ConsentKeys.consent) }
        defaults.set(true, forKey: ConsentKeys.asked)
    }

    /// „Nicht senden“ in der Abfrage: wird nicht erneut gefragt (Profil → Datenschutz bleibt erreichbar).
    public func declineClaudeConsent() {
        defaults.removeObject(forKey: ConsentKeys.consent)
        defaults.set(true, forKey: ConsentKeys.asked)
    }

    /// Widerruf: ab sofort kein Erholungskontext mehr; die Frage kommt nicht von selbst wieder.
    public func revokeClaudeConsent() {
        declineClaudeConsent()
    }

    /// „Alle Daten löschen“: Einwilligung und Entscheidung vergessen. Der PO trägt den Aufruf in `deleteAllData()` ein.
    public func resetConsentState() {
        for key in ConsentKeys.all { defaults.removeObject(forKey: key) }
    }

    // MARK: Erholungskontext

    /// Check-ins (ohne „Überspringen“) der letzten 14 Tage, Aufwärm-Check-Trend und Wellness-Anbieter, immer lokal und relativ.
    func recoverySummary(now: Date = .now) -> RecoverySummary? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(Self.recoveryWindowDays - 1), to: today) ?? today
        let rows = (try? context.fetch(FetchDescriptor<StoredCheckIn>())) ?? []
        let answers = rows.filter { !$0.isDeleted && !$0.skipped && $0.day >= start }.map(\.answers)
        let warmup = warmupTrend().direction
        let wellness = Self.recoveryWellnessProvider?.recoveryWellness(today: today)
        return RecoverySummary.make(.init(wellness: wellness, checkIns: answers, warmup: warmup))
    }

    /// Nur mit Einwilligung; sonst `nil` (zentrale Stelle für `planContext`).
    func consentedRecoverySummary(now: Date = .now) -> RecoverySummary? {
        claudeConsent == nil ? nil : recoverySummary(now: now)
    }

    /// Genau die Zeilen, die an Claude gehen würden (Vorschau, auch ohne Einwilligung).
    public func recoveryPreviewText(now: Date = .now) -> String {
        guard let summary = recoverySummary(now: now) else {
            return "Aktuell gibt es nichts zu senden: Es liegen keine Check-ins oder Erholungswerte vor."
        }
        return PlanPrompt.recoverySection(summary).joined(separator: "\n")
    }

    /// Beim ersten Planen fragen, sobald es Erholungsdaten gibt (Health aktiv oder Check-ins) und noch nicht entschieden wurde.
    public func needsClaudeConsentPrompt(now: Date = .now) -> Bool {
        guard claudeConsent == nil, !defaults.bool(forKey: ConsentKeys.asked) else { return false }
        return healthEnabled || recoverySummary(now: now) != nil
    }
}
