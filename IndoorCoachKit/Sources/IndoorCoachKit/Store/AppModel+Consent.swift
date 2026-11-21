import Foundation
import SwiftData

/// Einwilligung des Fahrers, dass Erholungskontext, Kraft-/Fremdsport-Einheiten und Health-Workouts (aggregiert) an Claude (Anthropic) gehen
/// (docs/17 §2.3, §9.1 Prinzip 5; Apple-Richtlinie 5.1.2(i)). Ohne gültige Einwilligung geht nichts aus Apple Health, kein Kraft-/Fremdsport-Abschnitt und kein Check-in an Claude.
/// Version 2: Kraft, andere Sportarten und Health-Workouts kamen dazu, ältere Einwilligungen gelten nicht mehr.
public struct ClaudeConsent: Codable, Equatable, Sendable {
    /// Erhöhen, wenn sich ändert, was an Claude geht: bestehende Einwilligungen gelten dann nicht mehr.
    public static let currentVersion = 2

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

    /// „Nicht senden“ in der Abfrage: wird nicht erneut gefragt (Profil → Coach · Claude bleibt erreichbar).
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
        let wellness = Self.recoveryWellnessProvider?.recoveryWellness(today: today) ?? recoveryWellnessFromHealth(now: now)
        return RecoverySummary.make(.init(wellness: wellness, checkIns: answers, warmup: warmup))
    }

    /// Ohne Einwilligung bleibt alles aus Apple Health draußen: Fahrten aus Health fallen weg, bei zusammengeführten Fahrten
    /// auch der Puls (er kann aus Health stammen).
    static func withoutHealthData(_ rides: [RideSummary]) -> [RideSummary] {
        rides.filter { $0.healthUUID == nil && !$0.isForeignSport }.map { ride in
            guard ride.healthNote != nil else { return ride }
            var copy = ride
            copy.averageHeartrate = nil
            copy.maxHeartrate = nil
            return copy
        }
    }

    /// Genau die Zeilen, die an Claude gehen würden (Vorschau, auch ohne Einwilligung).
    public func recoveryPreviewText(now: Date = .now) -> String {
        var lines: [String] = []
        if let summary = recoverySummary(now: now) { lines += PlanPrompt.recoverySection(summary) }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let strength = strengthWeekSummary(now: now, horizonStart: today, horizonEnd: today, calendar: calendar)
        let other = OtherSportSummary.summaries(from: allRides(), ftp: profile.ftp, thresholdHeartRate: profile.thresholdHeartRate,
                                                today: today, calendar: calendar)
        let training = PlanPrompt.strengthAndOtherSection(strength: strength, otherSports: other)
        if !training.isEmpty { lines += (lines.isEmpty ? [] : [""]) + training }
        guard !lines.isEmpty else {
            return "Aktuell gibt es nichts zu senden: Es liegen keine Check-ins, Erholungswerte, Kraft- oder Fremdsport-Einheiten vor."
        }
        return lines.joined(separator: "\n")
    }

    /// Beim ersten Planen fragen, sobald es Erholungsdaten gibt (Health aktiv oder Check-ins) und noch nicht entschieden wurde.
    public func needsClaudeConsentPrompt(now: Date = .now) -> Bool {
        guard claudeConsent == nil else { return false }
        // Eine Einwilligung älterer Version gilt nicht mehr: neu fragen, auch wenn schon einmal entschieden wurde.
        let outdated = defaults.data(forKey: ConsentKeys.consent) != nil
        guard outdated || !defaults.bool(forKey: ConsentKeys.asked) else { return false }
        return outdated || healthEnabled || recoverySummary(now: now) != nil || hasTrainingDataForClaude(now: now)
    }

    /// Gibt es Kraft- oder Fremdsport-Einheiten, die mit Einwilligung an Claude gingen?
    private func hasTrainingDataForClaude(now: Date) -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        if strengthWeekSummary(now: now, horizonStart: today, horizonEnd: today, calendar: calendar) != nil { return true }
        return allRides().contains { $0.isForeignSport }
    }
}
