import Foundation
import SwiftData

/// Eingaben aus dem Abschluss-Sheet einer aufgezeichneten Krafteinheit.
public struct StrengthDraft: Equatable, Sendable {
    public var templateName: String?
    public var exercises: [PerformedExercise]
    public var exertion: Int?
    public var legShare: LegInvolvement?
    public var note: String
    /// Sportart bei „Andere Einheit“ (nil = Krafttraining).
    public var sportName: String?

    public init(templateName: String? = nil, exercises: [PerformedExercise] = [], exertion: Int? = nil,
                legShare: LegInvolvement? = nil, note: String = "", sportName: String? = nil) {
        self.templateName = templateName; self.exercises = exercises; self.exertion = exertion
        self.legShare = legShare; self.note = note; self.sportName = sportName
    }

    /// Abschluss einer aufgezeichneten „Anderen Einheit“: Beine nur bei muskulärer Sportart (wie beim Nachtragen).
    public static func otherSport(_ sport: String, exertion: Int?, legShare: LegInvolvement?, note: String) -> StrengthDraft {
        let muscular = SportClassification.category(for: sport).feedsMuscleTrack
        return StrengthDraft(exertion: exertion, legShare: muscular ? legShare : nil,
                             note: note.trimmingCharacters(in: .whitespacesAndNewlines), sportName: sport)
    }
}

/// Krafttraining (B42, B43, B45): speichern, lesen, löschen, Muskel-Last, Vorlagen, Studio-Tage.
///
/// Vorlagen und Studio-Tage liegen als JSON in den UserDefaults (klein, ohne Migration, „Alle Daten löschen“
/// räumt sie auf). Einheiten liegen in SwiftData (`StoredStrengthSession`).
extension AppModel {
    enum StrengthKeys {
        static let templates = Keys.strengthTemplates
        static let days = Keys.strengthDays
    }

    // MARK: Lesen

    /// Alle Zeilen, neueste zuerst (Krafttraining und „Andere Einheit“).
    public func storedStrengthRows() -> [StoredStrengthSession] {
        ((try? context.fetch(FetchDescriptor<StoredStrengthSession>(sortBy: [SortDescriptor(\.start, order: .reverse)]))) ?? [])
            .filter { !$0.isDeleted }
    }

    /// Einheiten der Muskel-Spur (Kraft, Bouldern …), neueste zuerst.
    public func strengthSessions() -> [StrengthSession] {
        storedStrengthRows().filter(\.feedsMuscleTrack).map(\.session)
    }

    public func muscleLoad72h(now: Date = .now) -> MuscleLoad.Sum {
        MuscleLoad.sum(of: strengthSessions(), endingAt: now)
    }

    public func muscleLoadThisWeek(now: Date = .now, calendar: Calendar = .current) -> MuscleLoad.Sum {
        MuscleLoad.weeklySum(of: strengthSessions(), weekContaining: now, calendar: calendar)
    }

    /// „Wie letzte Woche“: Übungen und Vorwerte der jüngsten passenden Einheit (nur echtes Krafttraining).
    public func lastWeekTemplate(named name: String? = nil) -> StrengthTemplate? {
        let sessions = storedStrengthRows().filter { !$0.isOtherSport }.map(\.session)
        return StrengthTemplate.lastWeek(named: name, in: sessions)
    }

    // MARK: Schreiben

    /// Nachtragen ohne Aufzeichnung (< 15 s) oder „Andere Einheit“ (`sportName`). Nil bei Dauer ≤ 0.
    @discardableResult
    public func saveStrengthManual(start: Date, durationMinutes: Int, exertion: Int?, legShare: LegInvolvement?,
                                   exercises: [PerformedExercise], templateName: String? = nil, note: String = "",
                                   sportName: String? = nil, isDemo: Bool = false) -> StoredStrengthSession? {
        guard durationMinutes > 0 else { return nil }
        let session = StrengthSession(start: start, durationSeconds: durationMinutes * 60, source: .manual,
                                      exertion: exertion.map { min(max($0, 0), 10) }, legShare: legShare,
                                      exercises: exercises, templateName: templateName, note: note)
        let row = StoredStrengthSession(session: session, sportName: sportName, isDemo: isDemo)
        context.insert(row)
        guard saveReportingErrors("Die Einheit") else { return nil }
        return row
    }

    /// Aufgezeichnete Einheit (Brustgurt) mit den Angaben aus dem Abschluss-Sheet speichern. Der Puls kommt aus dem
    /// Ergebnis; Lücken (0) bleiben Lücken. Nil bei Dauer ≤ 0.
    @discardableResult
    public func saveStrength(from result: RecordingResult, draft: StrengthDraft) -> StoredStrengthSession? {
        let seconds = Int(result.duration.rounded())
        guard seconds > 0 else { return nil }
        let session = StrengthSession(id: result.id, start: result.startedAt, durationSeconds: seconds, source: .recorded,
                                      exertion: draft.exertion.map { min(max($0, 0), 10) }, legShare: draft.legShare,
                                      exercises: draft.exercises, templateName: draft.templateName, note: draft.note)
        let row = StoredStrengthSession(session: session, heartRate: result.seconds.heartRate, sportName: draft.sportName)
        context.insert(row)
        guard saveReportingErrors("Die Einheit", hint: Self.recordingKeptHint) else { return nil }
        exportToHealth(row)   // nur wenn für die Sportart eingeschaltet (Profil → Dienste & Geräte → Apple Health)
        return row
    }

    /// Zeit in Pulszonen einer aufgezeichneten Einheit (nur Puls, keine Watt-Zonen); nil ohne Pulsspur.
    public func heartZoneTime(for row: StoredStrengthSession) -> ZoneTime.Result? {
        guard let hr = row.heartRateSeries, hr.contains(where: { $0 > 0 }) else { return nil }
        let seconds = RideSeconds(power: Array(repeating: 0, count: hr.count), heartRate: hr)
        return ZoneTime.compute(seconds, ftp: profile.ftp, heartRate: heartRateZones())
    }

    /// Ergänzt ein Apple-Health-Workout um Härte und Beine (für das HealthKit-Paket). Gleiche `id` aktualisiert die
    /// vorhandene Zeile. `sport` ist ein HealthKit-Name oder eine deutsche Bezeichnung (`SportClassification`);
    /// reines Krafttraining wird als Kraft gespeichert, alles andere als „Andere Einheit“ mit Sportart.
    @discardableResult
    public func annotate(healthWorkout id: String, start: Date, duration: TimeInterval, sport: String,
                         hardness: Int?, legs: LegInvolvement?) -> StoredStrengthSession? {
        let seconds = Int(duration.rounded())
        guard seconds > 0 else { return nil }
        let clamped = hardness.map { min(max($0, 0), 10) }
        let strengthNames: Set<String> = ["traditionalstrengthtraining", "functionalstrengthtraining", "kraft", "krafttraining"]
        let sportName: String? = strengthNames.contains(SportClassification.normalize(sport)) ? nil : sport
        if let existing = storedStrengthRows().first(where: { $0.healthUUID == id }) {
            existing.start = start
            existing.durationSeconds = seconds
            existing.exertion = clamped
            existing.legShareRaw = legs?.rawValue
            existing.sportName = sportName
            guard saveReportingErrors("Die Einheit") else { return nil }
            return existing
        }
        let session = StrengthSession(start: start, durationSeconds: seconds, source: .healthAnnotation,
                                      exertion: clamped, legShare: legs)
        let row = StoredStrengthSession(session: session, healthUUID: id, sportName: sportName)
        context.insert(row)
        guard saveReportingErrors("Die Einheit") else { return nil }
        return row
    }

    public func deleteStrength(_ row: StoredStrengthSession) {
        context.delete(row)
        saveReportingErrors("Das Löschen")
    }

    // MARK: Vorlagen und Studio-Tage

    public func strengthTemplates() -> [StrengthTemplate] {
        defaults.data(forKey: StrengthKeys.templates).flatMap { try? JSONDecoder().decode([StrengthTemplate].self, from: $0) } ?? []
    }

    /// Speichert eine Vorlage; eine gleichnamige (ohne Beachtung der Schreibweise) wird an ihrer Stelle ersetzt.
    public func saveStrengthTemplate(_ template: StrengthTemplate) {
        let name = template.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        var t = template
        t.name = name
        var all = strengthTemplates()
        if let i = all.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) { all[i] = t } else { all.append(t) }
        writeTemplates(all)
    }

    public func deleteStrengthTemplate(named name: String) {
        writeTemplates(strengthTemplates().filter { $0.name.lowercased() != name.lowercased() })
    }

    private func writeTemplates(_ all: [StrengthTemplate]) {
        if all.isEmpty { defaults.removeObject(forKey: StrengthKeys.templates); return }
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: StrengthKeys.templates) }
    }

    /// Studio-Tage als Kalender-Wochentage (1 = Sonntag … 7 = Samstag). Eigene Persistenz, nicht im `AthleteProfile`.
    public var strengthDays: Set<Int> {
        get { Set((defaults.array(forKey: StrengthKeys.days) as? [Int] ?? []).filter { (1...7).contains($0) }) }
        set {
            let valid = newValue.filter { (1...7).contains($0) }.sorted()
            if valid.isEmpty { defaults.removeObject(forKey: StrengthKeys.days) } else { defaults.set(valid, forKey: StrengthKeys.days) }
        }
    }

    /// Das Datum liegt auf einem Studio-Tag.
    public func isStrengthDay(_ date: Date = .now, calendar: Calendar = .current) -> Bool {
        strengthDays.contains(calendar.component(.weekday, from: date))
    }

    // MARK: Löschen

    func deleteAllStrengthData() {
        try? context.delete(model: StoredStrengthSession.self)
        defaults.removeObject(forKey: StrengthKeys.templates)
        defaults.removeObject(forKey: StrengthKeys.days)
    }
}
