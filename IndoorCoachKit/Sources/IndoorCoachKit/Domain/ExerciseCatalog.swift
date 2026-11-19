import Foundation

/// Muskelgruppen des Übungskatalogs.
public enum MuscleGroup: String, Codable, Sendable, CaseIterable {
    case legsFront, legsBack, glutes, calves, core, back, chest, shoulders, arms

    public var label: String {
        switch self {
        case .legsFront: "Beine vorn"
        case .legsBack: "Beine hinten"
        case .glutes: "Gesäß"
        case .calves: "Waden"
        case .core: "Rumpf"
        case .back: "Rücken"
        case .chest: "Brust"
        case .shoulders: "Schultern"
        case .arms: "Arme"
        }
    }
}

/// Katalogübung. Die `id` ist stabil und wird in `PerformedExercise` und Vorlagen gespeichert.
public struct Exercise: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var name: String
    public var muscles: [MuscleGroup]
    public var legInvolvement: LegInvolvement
    /// Sonder-Eintrag (z. B. Bouldern/Klettern), kein klassischer Satz-Wdh-Ablauf.
    public var isSpecial: Bool

    public init(id: String, name: String, muscles: [MuscleGroup], legs: LegInvolvement, isSpecial: Bool = false) {
        self.id = id; self.name = name; self.muscles = muscles; self.legInvolvement = legs; self.isSpecial = isSpecial
    }
}

/// Übungskatalog (O15: Auswahl, Muskelgruppen und Beinanteil sind Vorschläge, der PO bestätigt).
///
/// Beinanteil-Faustregel: „schwer“ = große Beinmuskeln mit hoher Last (Kniebeuge, Kreuzheben, Ausfallschritt …),
/// „leicht“ = Isolation, geringe Last oder Nebenbeteiligung, „keine“ = Rumpf und Oberkörper.
public enum ExerciseCatalog {
    public static let all: [Exercise] = [
        // Beine
        Exercise(id: "squat", name: "Kniebeuge", muscles: [.legsFront, .glutes, .core], legs: .heavy),
        Exercise(id: "front_squat", name: "Frontkniebeuge", muscles: [.legsFront, .glutes, .core], legs: .heavy),
        Exercise(id: "deadlift", name: "Kreuzheben", muscles: [.legsBack, .glutes, .back], legs: .heavy),
        Exercise(id: "romanian_deadlift", name: "Rumänisches Kreuzheben", muscles: [.legsBack, .glutes, .back], legs: .heavy),
        Exercise(id: "leg_press", name: "Beinpresse", muscles: [.legsFront, .glutes], legs: .heavy),
        Exercise(id: "lunge", name: "Ausfallschritt", muscles: [.legsFront, .glutes], legs: .heavy),
        Exercise(id: "bulgarian_split_squat", name: "Bulgarian Split Squat", muscles: [.legsFront, .glutes], legs: .heavy),
        Exercise(id: "step_up", name: "Step-up", muscles: [.legsFront, .glutes], legs: .heavy),
        Exercise(id: "hip_thrust", name: "Hip Thrust", muscles: [.glutes, .legsBack], legs: .heavy),
        Exercise(id: "kettlebell_swing", name: "Kettlebell Swing", muscles: [.glutes, .legsBack, .back], legs: .heavy),
        Exercise(id: "leg_extension", name: "Beinstrecker", muscles: [.legsFront], legs: .light),
        Exercise(id: "leg_curl", name: "Beinbeuger", muscles: [.legsBack], legs: .light),
        Exercise(id: "calf_raise", name: "Wadenheben", muscles: [.calves], legs: .light),
        Exercise(id: "goblet_squat", name: "Goblet Squat", muscles: [.legsFront, .glutes, .core], legs: .light),
        Exercise(id: "box_jump", name: "Box Jump", muscles: [.legsFront, .glutes, .calves], legs: .light),
        Exercise(id: "good_morning", name: "Good Morning", muscles: [.legsBack, .back, .glutes], legs: .light),
        Exercise(id: "back_extension", name: "Back Extension", muscles: [.back, .glutes], legs: .light),
        Exercise(id: "farmers_walk", name: "Farmer's Walk", muscles: [.core, .arms, .shoulders], legs: .light),
        Exercise(id: "burpee", name: "Burpee", muscles: [.legsFront, .chest, .core], legs: .light),
        Exercise(id: "mountain_climber", name: "Mountain Climber", muscles: [.core, .shoulders], legs: .light),
        // Rumpf
        Exercise(id: "plank", name: "Plank", muscles: [.core], legs: .none),
        Exercise(id: "side_plank", name: "Seitstütz", muscles: [.core], legs: .none),
        Exercise(id: "dead_bug", name: "Dead Bug", muscles: [.core], legs: .none),
        Exercise(id: "bird_dog", name: "Bird Dog", muscles: [.core, .back], legs: .none),
        Exercise(id: "pallof_press", name: "Pallof Press", muscles: [.core], legs: .none),
        Exercise(id: "russian_twist", name: "Russian Twist", muscles: [.core], legs: .none),
        Exercise(id: "hanging_leg_raise", name: "Hängendes Beinheben", muscles: [.core, .arms], legs: .none),
        // Oberkörper
        Exercise(id: "pull_up", name: "Klimmzug", muscles: [.back, .arms], legs: .none),
        Exercise(id: "lat_pulldown", name: "Latzug", muscles: [.back, .arms], legs: .none),
        Exercise(id: "row_cable", name: "Rudern (Kabel)", muscles: [.back, .arms], legs: .none),
        Exercise(id: "row_dumbbell", name: "Rudern (Kurzhantel)", muscles: [.back, .arms], legs: .none),
        Exercise(id: "bench_press", name: "Bankdrücken", muscles: [.chest, .shoulders, .arms], legs: .none),
        Exercise(id: "push_up", name: "Liegestütz", muscles: [.chest, .shoulders, .arms, .core], legs: .none),
        Exercise(id: "shoulder_press", name: "Schulterdrücken", muscles: [.shoulders, .arms], legs: .none),
        Exercise(id: "lateral_raise", name: "Seitheben", muscles: [.shoulders], legs: .none),
        Exercise(id: "face_pull", name: "Face Pull", muscles: [.shoulders, .back], legs: .none),
        Exercise(id: "biceps_curl", name: "Bizeps-Curl", muscles: [.arms], legs: .none),
        Exercise(id: "dips", name: "Dips", muscles: [.chest, .arms], legs: .none),
        Exercise(id: "triceps_pushdown", name: "Trizeps-Drücken", muscles: [.arms], legs: .none),
        // Sonder-Eintrag
        Exercise(id: "climbing", name: "Bouldern/Klettern", muscles: [.back, .arms, .core], legs: .light, isSpecial: true),
    ]

    private static let byID: [String: Exercise] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func exercise(id: String) -> Exercise? { byID[id] }

    public static func exercises(for group: MuscleGroup) -> [Exercise] {
        all.filter { $0.muscles.contains(group) }
    }

    /// Beinanteil einer Übungsliste: schwer, wenn mindestens eine ausgeführte „schwer“-Übung (Häkchen oder Volumen);
    /// sonst leicht bei einer ausgeführten „leicht“-Übung; sonst keine. Unbekannte IDs zählen nicht.
    public static func legShare(for exercises: [PerformedExercise]) -> LegInvolvement {
        exercises
            .filter(\.isPerformed)
            .compactMap { byID[$0.exerciseID]?.legInvolvement }
            .max() ?? .none
    }
}
