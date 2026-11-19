import Foundation
import SwiftData

/// Eine Krafteinheit oder „Andere Einheit“ (docs/17 §6.2 J-B, B42). Alle Attribute optional oder mit Standardwert,
/// damit bestehende Stores leichtgewichtig migrieren. Zählt nicht in CTL/ATL.
@Model
public final class StoredStrengthSession {
    @Attribute(.unique) public var id: UUID = UUID()
    public var start: Date = Date.now
    public var durationSeconds: Int = 0
    /// `StrengthSource.rawValue`.
    public var sourceRaw: String = StrengthSource.manual.rawValue
    /// Workout-ID aus Apple Health (Annotation), sonst nil.
    public var healthUUID: String?
    /// Härte nach CR-10 (0–10).
    public var exertion: Int?
    /// `LegInvolvement.rawValue`; nil = aus den Übungen ableiten.
    public var legShareRaw: String?
    /// JSON von `[PerformedExercise]`.
    public var exercisesData: Data?
    public var templateName: String?
    public var note: String = ""
    /// Puls pro Sekunde, 1 Byte je Sekunde (0 = Lücke).
    @Attribute(.externalStorage) public var heartRateSeconds: Data?
    /// Sportart bei „Andere Einheit“ (nil = Krafttraining).
    public var sportName: String?
    /// Hinweis, wenn ein Health-Workout mit dieser Einheit zusammengeführt wurde (nur Anzeige).
    public var healthNote: String?
    public var isDemo: Bool = false

    public init(session: StrengthSession, healthUUID: String? = nil, heartRate: [UInt8]? = nil,
                sportName: String? = nil, isDemo: Bool = false) {
        id = session.id
        start = session.start
        durationSeconds = session.durationSeconds
        sourceRaw = session.source.rawValue
        self.healthUUID = healthUUID
        exertion = session.exertion
        legShareRaw = session.legShare?.rawValue
        exercisesData = session.exercises.isEmpty ? nil : try? JSONEncoder().encode(session.exercises)
        templateName = session.templateName
        note = session.note
        heartRateSeconds = heartRate.flatMap { $0.contains { $0 > 0 } ? Data($0) : nil }
        self.sportName = sportName
        self.isDemo = isDemo
    }

    public var source: StrengthSource { StrengthSource(rawValue: sourceRaw) ?? .manual }
    public var exercises: [PerformedExercise] {
        exercisesData.flatMap { try? JSONDecoder().decode([PerformedExercise].self, from: $0) } ?? []
    }
    public var heartRateSeries: [UInt8]? { heartRateSeconds.map { [UInt8]($0) } }

    /// Sportart ist „Andere Einheit“ (nicht Krafttraining).
    public var isOtherSport: Bool { sportName != nil }

    /// Fließt in die Muskel-Spur: Krafttraining oder eine als muskulär klassifizierte Sportart.
    public var feedsMuscleTrack: Bool {
        guard let sportName else { return true }
        return SportClassification.category(for: sportName).feedsMuscleTrack
    }

    /// Domänenwert. Der Beinanteil fällt bei Sportarten mit fester Beinwirkung (Bouldern) auf deren Vorgabe zurück.
    public var session: StrengthSession {
        var leg = legShareRaw.flatMap(LegInvolvement.init(rawValue:))
        if leg == nil, let sportName { leg = SportClassification.defaultLegShare(for: sportName) }
        return StrengthSession(id: id, start: start, durationSeconds: durationSeconds, source: source, exertion: exertion,
                               legShare: leg, exercises: exercises, templateName: templateName, note: note)
    }
}
