import Foundation

/// Zuordnung einer Sportart zu einer Belastungs-Spur (docs/17 §8.2, B45).
public enum SportCategory: String, Codable, Sendable, CaseIterable {
    /// Rad: Rad-PMC über Leistung.
    case cycling
    /// Aerobe Fremdsportart: Rad-PMC über Puls-TSS (geschätzt).
    case aerobic
    /// Kraft, Rumpf, Bouldern: Muskel-Spur.
    case muscular
    /// Gemischt (z. B. HIIT): Nutzer entscheidet.
    case mixed
    /// Keine Belastungsrechnung.
    case ignore

    public var feedsBikeLoad: Bool { self == .cycling }
    public var feedsAerobicLoad: Bool { self == .aerobic }
    public var feedsMuscleTrack: Bool { self == .muscular }
    public var needsUserDecision: Bool { self == .mixed }
}

/// Klassifiziert Sportart-Namen, ohne HealthKit zu importieren. Akzeptiert die Namen der HealthKit-Workout-Typen
/// (`indoorCycling`, `HKWorkoutActivityTypeRunning`, `TRADITIONAL_STRENGTH_TRAINING` …) und deutsche Bezeichnungen.
public enum SportClassification {
    public static func category(for name: String) -> SportCategory {
        table[normalize(name)] ?? .ignore
    }

    /// Vorbelegung des Beinanteils für Sportarten mit fester Beinwirkung, sonst `nil` (aus Übungen ableiten).
    public static func defaultLegShare(for name: String) -> LegInvolvement? {
        switch normalize(name) {
        case "climbing", "bouldern", "klettern": .light
        case "coretraining": LegInvolvement.none
        default: nil
        }
    }

    /// SF-Symbol der Sportart (HealthKit-Name oder deutsche Bezeichnung) für Verlauf und Detail; Standard: allgemeines Training.
    public static func symbol(for name: String) -> String {
        switch normalize(name) {
        case "running", "laufen", "laufband": "figure.run"
        case "walking", "gehen": "figure.walk"
        case "hiking", "wandern": "figure.hiking"
        case "swimming", "schwimmen": "figure.pool.swim"
        case "rowing", "rudern", "rudergerät": "figure.rower"
        case "elliptical", "crosstrainer": "figure.elliptical"
        case "crosscountryskiing", "langlauf": "figure.skiing.crosscountry"
        case "downhillskiing", "ski", "skifahren": "figure.skiing.downhill"
        case "snowboarding": "figure.snowboarding"
        case "skatingsports": "figure.skating"
        case "stairclimbing", "stairs", "steptraining": "figure.stair.stepper"
        case "paddlesports": "oar.2.crossed"
        case "cycling", "indoorcycling", "handcycling", "rad", "radfahren": "figure.outdoor.cycle"
        default: "figure.mixed.cardio"
        }
    }

    static func normalize(_ name: String) -> String {
        var s = name.lowercased().filter { $0.isLetter || $0.isNumber }
        for prefix in ["hkworkoutactivitytype", "hkworkout"] where s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
        }
        return s
    }

    private static let table: [String: SportCategory] = {
        var t: [String: SportCategory] = [:]
        func add(_ category: SportCategory, _ names: [String]) { for n in names { t[normalize(n)] = category } }
        add(.cycling, ["cycling", "indoorCycling", "handCycling", "Rad", "Radfahren", "Rolle"])
        add(.aerobic, ["running", "walking", "hiking", "crossCountrySkiing", "downhillSkiing", "snowboarding",
                       "skatingSports", "rowing", "elliptical", "swimming", "stairClimbing", "stairs", "stepTraining",
                       "paddleSports", "Laufen", "Laufband", "Gehen", "Wandern", "Langlauf", "Ski", "Skifahren",
                       "Rudern", "Rudergerät", "Crosstrainer", "Schwimmen", "Kurs", "Gruppenkurs", "Aerobic"])
        add(.muscular, ["traditionalStrengthTraining", "functionalStrengthTraining", "coreTraining", "climbing",
                        "flexibility", "pilates", "barre", "Kraft", "Krafttraining", "Bouldern", "Klettern", "Rumpf"])
        add(.mixed, ["hiit", "highIntensityIntervalTraining", "crossTraining", "mixedCardio", "mixedMetabolicCardioTraining",
                     "jumpRope", "boxing", "kickboxing", "martialArts"])
        add(.ignore, ["yoga", "mindAndBody", "taiChi", "cooldown", "preparationAndRecovery", "other", "Sonstiges"])
        return t
    }()
}
