import Foundation

/// Vorlage für Krafteinheiten: Übungen in fester Reihenfolge mit optionalen Vorwerten.
public struct StrengthTemplate: Identifiable, Codable, Hashable, Sendable {
    /// Anzeigename der automatisch erzeugten „wie letzte Woche“-Vorlage.
    public static let lastWeekName = "Wie letzte Woche"

    public var name: String
    public var exerciseIDs: [String]
    /// Vorwerte je Übungs-ID.
    public var defaults: [String: SetDefaults]

    public var id: String { name }

    public init(name: String, exerciseIDs: [String], defaults: [String: SetDefaults] = [:]) {
        self.name = name; self.exerciseIDs = exerciseIDs; self.defaults = defaults
    }

    /// Vorlage aus einer vergangenen Einheit; Vorwerte nur, wo etwas angegeben war.
    public static func from(session: StrengthSession, name: String) -> StrengthTemplate {
        var defaults: [String: SetDefaults] = [:]
        for e in session.exercises where !e.setDefaults.isEmpty { defaults[e.exerciseID] = e.setDefaults }
        return StrengthTemplate(name: name, exerciseIDs: session.exercises.map(\.exerciseID), defaults: defaults)
    }

    /// „Wie letzte Woche“: mit Namen die jüngste Einheit dieser Vorlage (ohne Beachtung der Groß-/Kleinschreibung),
    /// ohne Namen die jüngste Einheit mit Vorwerten, sonst die jüngste mit Übungen. `nil`, wenn nichts passt.
    public static func lastWeek(named name: String?, in sessions: [StrengthSession]) -> StrengthTemplate? {
        let withExercises = sessions.filter { !$0.exercises.isEmpty }
        if let name {
            let wanted = name.lowercased()
            guard let s = withExercises
                .filter({ $0.templateName?.lowercased() == wanted })
                .max(by: { $0.start < $1.start }) else { return nil }
            return from(session: s, name: name)
        }
        let withVolume = withExercises.filter { $0.exercises.contains { !$0.setDefaults.isEmpty } }
        guard let s = (withVolume.isEmpty ? withExercises : withVolume).max(by: { $0.start < $1.start }) else { return nil }
        return from(session: s, name: lastWeekName)
    }

    /// Frische Übungsliste für eine neue Einheit: Vorwerte kopiert, noch nicht abgehakt.
    public func makeExercises() -> [PerformedExercise] {
        exerciseIDs.map { id in
            let d = defaults[id]
            return PerformedExercise(exerciseID: id, sets: d?.sets, reps: d?.reps, weightKg: d?.weightKg, checked: false)
        }
    }

    /// Vorbelegung des Beinanteils, als wären alle Übungen gemacht.
    public var suggestedLegShare: LegInvolvement {
        ExerciseCatalog.legShare(for: exerciseIDs.map { PerformedExercise(exerciseID: $0) })
    }
}
