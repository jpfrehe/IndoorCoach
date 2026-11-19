import Foundation
import SwiftData

/// Hinweis „Schwere Beine – tauschen?“ an einer geplanten Schlüsseleinheit (W3-C, B49, docs/17 §8.2, O16).
/// Die Regeln sind Faustregeln: nie eine automatische Planänderung, nur ein Vorschlag mit drei Aktionen.
public struct LegLoadHint {
    public var conflict: MuscleLoad.Conflict
    /// Kurzname der schweren Einheit, z. B. „Kniebeuge“.
    public var sessionName: String
    public var exertion: Int?
    /// Nächste geplante Grundlage-/Regenerationseinheit nach der Schlüsseleinheit; `nil` = nichts zum Tauschen.
    public var base: StoredWorkout?
    /// „gestern“, „heute“ oder „vor X h“.
    public var whenText: String

    public var message: String {
        let detail = exertion.map { "\(sessionName), Härte \($0)" } ?? sessionName
        var text = "Schwere Beine \(whenText) (\(detail)). Faustregel: 24 h Abstand."
        if let base { text += " Mit \(base.title) tauschen?" } else { text += " Leichter machen?" }
        return text
    }
}

extension AppModel {
    static let legLoadKeptKey = Keys.legLoadKept

    private static let keyTypes: [WorkoutType: MuscleLoad.KeyIntensity] = [
        .vo2max: .vo2, .threshold: .threshold, .anaerobic: .anaerobic
    ]

    // MARK: Plan-Kontext

    /// Krafteinheiten der letzten 7 Tage und Studio-Tage im Planungszeitraum; `nil`, wenn es nichts davon gibt.
    func strengthWeekSummary(now: Date, horizonStart: Date, horizonEnd: Date, calendar: Calendar) -> StrengthWeekSummary? {
        let since = now.addingTimeInterval(-7 * 86400)
        let sessions = strengthSessions().filter { $0.start >= since && $0.start <= now }
            .map { StrengthWeekSummary.Entry(date: $0.start, exertion: $0.validExertion, minutes: Int($0.durationMinutes.rounded()),
                                             legs: $0.effectiveLegShare) }
        var studio: [Date] = []
        let days = strengthDays
        if !days.isEmpty {
            var d = calendar.startOfDay(for: horizonStart)
            let last = calendar.startOfDay(for: horizonEnd)
            while d <= last {
                if days.contains(calendar.component(.weekday, from: d)) { studio.append(d) }
                guard let next = calendar.date(byAdding: .day, value: 1, to: d) else { break }
                d = next
            }
        }
        if sessions.isEmpty && studio.isEmpty { return nil }
        return StrengthWeekSummary(sessions: sessions, studioDays: studio)
    }

    // MARK: Banner

    /// Hinweis für eine geplante Schlüsseleinheit, oder `nil` (kein Konflikt, schon bestätigt, nicht geplant, vergangen).
    public func legLoadHint(for workout: StoredWorkout, now: Date = .now) -> LegLoadHint? {
        guard workout.status == .planned, !workout.isDeleted, let intensity = Self.keyTypes[workout.type],
              !isLegLoadKept(workout) else { return nil }
        let planned = startDate(for: workout)
        guard Calendar.current.startOfDay(for: workout.date) >= Calendar.current.startOfDay(for: now) else { return nil }
        let sessions = strengthSessions()
        guard let conflict = MuscleLoad.keySessionConflict(sessions: sessions, plannedKeySessionAt: planned, intensity: intensity),
              let session = sessions.first(where: { $0.id == conflict.sessionID }) else { return nil }
        let all = (try? context.fetch(FetchDescriptor<StoredWorkout>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let base = all.first { !$0.isDeleted && $0.status == .planned && $0.id != workout.id && $0.date > workout.date
            && ($0.type == .endurance || $0.type == .recovery) }
        return LegLoadHint(conflict: conflict, sessionName: Self.legLoadName(of: session), exertion: session.validExertion,
                           base: base, whenText: Self.whenText(end: session.end, planned: planned))
    }

    private static func legLoadName(of s: StrengthSession) -> String {
        let heavy = s.exercises.filter(\.isPerformed).compactMap { ExerciseCatalog.exercise(id: $0.exerciseID) }
            .first { $0.legInvolvement == .heavy }
        return heavy?.name ?? s.templateName ?? "Kraft"
    }

    private static func whenText(end: Date, planned: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(end, inSameDayAs: planned) { return "heute" }
        if let y = cal.date(byAdding: .day, value: -1, to: planned), cal.isDate(end, inSameDayAs: y) { return "gestern" }
        return "vor \(max(1, Int((planned.timeIntervalSince(end) / 3600).rounded()))) h"
    }

    // MARK: Aktionen

    /// Tauscht die Termine zweier geplanter Einheiten; Kalender und MyWhoosh ziehen nach. `false`, wenn nicht möglich.
    @discardableResult
    public func swapForLegLoad(_ workout: StoredWorkout, with other: StoredWorkout) async -> Bool {
        guard workout.id != other.id, workout.status == .planned, other.status == .planned,
              !workout.isDeleted, !other.isDeleted else { return false }
        let date = workout.date
        workout.date = other.date
        other.date = date
        try? context.save()
        let failedA = await propagateChange(of: workout)
        let failedB = await propagateChange(of: other)
        if !(failedA || failedB) { show("Termine getauscht: \(workout.title) und \(other.title).", error: false) }
        return true
    }

    /// „Leichter machen“: vorhandenes Anpassen um 10 %; der Hinweis verschwindet danach.
    public func lightenForLegLoad(_ workout: StoredWorkout) async {
        await adjust(workout, minutes: nil, easierBy: 10)
        keepLegLoad(workout)
    }

    /// „Behalten“: für diese Einheit keinen Hinweis mehr zeigen.
    public func keepLegLoad(_ workout: StoredWorkout) {
        var kept = Set(defaults.stringArray(forKey: Self.legLoadKeptKey) ?? [])
        kept.insert(workout.id.uuidString)
        defaults.set(kept.sorted(), forKey: Self.legLoadKeptKey)
    }

    public func isLegLoadKept(_ workout: StoredWorkout) -> Bool {
        (defaults.stringArray(forKey: Self.legLoadKeptKey) ?? []).contains(workout.id.uuidString)
    }
}
