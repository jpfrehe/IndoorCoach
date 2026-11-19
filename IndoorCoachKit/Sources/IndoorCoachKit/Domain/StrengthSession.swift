import Foundation

/// Beinanteil einer Krafteinheit (Muskel-Spur, docs/17 §8.2). Geordnet: keine < leicht < schwer.
public enum LegInvolvement: String, Codable, Sendable, CaseIterable, Comparable {
    case none, light, heavy

    private var rank: Int {
        switch self {
        case .none: 0
        case .light: 1
        case .heavy: 2
        }
    }

    public static func < (lhs: LegInvolvement, rhs: LegInvolvement) -> Bool { lhs.rank < rhs.rank }

    public var label: String {
        switch self {
        case .none: "keine"
        case .light: "leicht"
        case .heavy: "schwer"
        }
    }
}

/// Woher die Einheit stammt (bestimmt später das Quellenetikett).
public enum StrengthSource: String, Codable, Sendable, CaseIterable {
    /// Mit IndoorCoach aufgezeichnet (z. B. Brustgurt).
    case recorded
    /// Nachgetragen ohne Aufzeichnung.
    case manual
    /// Workout aus Apple Health, um Härte und Beine ergänzt.
    case healthAnnotation
}

/// Satzangaben als Vorwerte (Sätze × Wiederholungen × Gewicht).
public struct SetDefaults: Codable, Hashable, Sendable {
    public var sets: Int?
    public var reps: Int?
    public var weightKg: Double?

    public init(sets: Int? = nil, reps: Int? = nil, weightKg: Double? = nil) {
        self.sets = sets; self.reps = reps; self.weightKg = weightKg
    }

    public var isEmpty: Bool { sets == nil && reps == nil && weightKg == nil }
}

/// Eine ausgeführte Übung. Volumen ist optional, das Häkchen genügt.
public struct PerformedExercise: Codable, Hashable, Sendable {
    public var exerciseID: String
    public var sets: Int?
    public var reps: Int?
    public var weightKg: Double?
    /// Häkchen „gemacht“. Standard `true`, weil Übungen meist beim Abhaken entstehen.
    public var checked: Bool

    public init(exerciseID: String, sets: Int? = nil, reps: Int? = nil, weightKg: Double? = nil, checked: Bool = true) {
        self.exerciseID = exerciseID; self.sets = sets; self.reps = reps; self.weightKg = weightKg; self.checked = checked
    }

    /// Sätze oder Wiederholungen angegeben.
    public var hasVolume: Bool { (sets ?? 0) > 0 || (reps ?? 0) > 0 }

    /// Zählt als ausgeführt: Häkchen oder Volumen.
    public var isPerformed: Bool { checked || hasVolume }

    public var setDefaults: SetDefaults { SetDefaults(sets: sets, reps: reps, weightKg: weightKg) }
}

/// Eine Krafteinheit (auch Bouldern u. Ä.) für die Muskel-Spur. Reiner Value Type, keine Persistenz.
public struct StrengthSession: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var start: Date
    public var durationSeconds: Int
    public var source: StrengthSource
    /// Härte nach CR-10 (0–10), `nil` solange nicht angegeben.
    public var exertion: Int?
    /// Vom Nutzer bestätigter Beinanteil; `nil` = aus den Übungen ableiten.
    public var legShare: LegInvolvement?
    public var exercises: [PerformedExercise]
    /// Name der verwendeten Vorlage (für „wie letzte Woche“).
    public var templateName: String?
    public var note: String

    public init(id: UUID = UUID(), start: Date, durationSeconds: Int, source: StrengthSource = .manual,
                exertion: Int? = nil, legShare: LegInvolvement? = nil, exercises: [PerformedExercise] = [],
                templateName: String? = nil, note: String = "") {
        self.id = id; self.start = start; self.durationSeconds = durationSeconds; self.source = source
        self.exertion = exertion; self.legShare = legShare; self.exercises = exercises
        self.templateName = templateName; self.note = note
    }

    public var end: Date { start.addingTimeInterval(TimeInterval(max(0, durationSeconds))) }
    public var durationMinutes: Double { Double(max(0, durationSeconds)) / 60 }

    /// Härte nur, wenn sie auf der CR-10-Skala (0–10) liegt.
    public var validExertion: Int? { exertion.flatMap { (0...10).contains($0) ? $0 : nil } }

    /// Beinanteil: explizite Angabe, sonst aus den Übungen abgeleitet.
    public var effectiveLegShare: LegInvolvement { legShare ?? ExerciseCatalog.legShare(for: exercises) }
}
