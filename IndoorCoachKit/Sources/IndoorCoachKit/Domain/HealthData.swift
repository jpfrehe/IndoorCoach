import Foundation

// Plattformneutrale Werttypen für das lesende HealthKit-Paket (docs/17 §3.1, B46). Kein HealthKit-Import.

/// Quelle eines Health-Werts (Gerät/App), z. B. „Apple Watch“ oder „Garmin Connect“.
public struct HealthSourceRef: Hashable, Codable, Sendable {
    public var name: String
    public var bundleID: String

    public init(name: String, bundleID: String) {
        self.name = name
        self.bundleID = bundleID
    }
}

/// Ein Workout aus Health. `activityTypeName` passt zu `SportClassification` (z. B. `running`).
public struct HealthWorkout: Identifiable, Equatable, Sendable {
    public var uuid: UUID
    public var start: Date
    public var end: Date
    public var activityTypeName: String
    public var sourceName: String
    public var sourceBundleID: String
    /// Von der eigenen App geschrieben (späterer Export): wird beim Import ausgefiltert.
    public var isOwnSource: Bool
    public var avgHR: Double?
    public var maxHR: Double?
    public var energyKcal: Double?
    /// Indoor-Kennzeichen des Workouts (`HKMetadataKeyIndoorWorkout`); `false` ohne Angabe.
    public var isIndoor: Bool

    public var id: UUID { uuid }
    public var source: HealthSourceRef { HealthSourceRef(name: sourceName, bundleID: sourceBundleID) }
    public var category: SportCategory { SportClassification.category(for: activityTypeName) }

    public init(uuid: UUID, start: Date, end: Date, activityTypeName: String, sourceName: String, sourceBundleID: String,
                isOwnSource: Bool, avgHR: Double?, maxHR: Double?, energyKcal: Double?, isIndoor: Bool = false) {
        self.uuid = uuid
        self.start = start
        self.end = end
        self.activityTypeName = activityTypeName
        self.sourceName = sourceName
        self.sourceBundleID = sourceBundleID
        self.isOwnSource = isOwnSource
        self.avgHR = avgHR
        self.maxHR = maxHR
        self.energyKcal = energyKcal
        self.isIndoor = isIndoor
    }

    /// Rad auf der Rolle: Indoor-Kennzeichen oder der Typname `indoorCycling`.
    public var isIndoorCycling: Bool {
        category == .cycling && (isIndoor || SportClassification.normalize(activityTypeName) == "indoorcycling")
    }
}

extension Array where Element == HealthWorkout {
    /// Ohne Workouts der eigenen App (Echo-Schutz beim Import).
    public var importable: [HealthWorkout] { filter { !$0.isOwnSource } }
}

/// Tageskennzahlen. `wristTempDelta` liefert die nächtliche Handgelenktemperatur in °C (absolut); die Abweichung zur
/// persönlichen Basis rechnet der Verbraucher. `bodyMass` in kg, `sleepHours` in Stunden.
public enum HealthMetric: String, CaseIterable, Codable, Sendable {
    case restingHR, hrvSDNN, sleepHours, respiratoryRate, wristTempDelta, bodyMass
}

public struct HealthDaily: Equatable, Sendable {
    /// Beginn des Tages (Aufwachtag bei Schlaf).
    public var date: Date
    public var metric: HealthMetric
    public var value: Double
    public var source: HealthSourceRef

    public init(date: Date, metric: HealthMetric, value: Double, source: HealthSourceRef) {
        self.date = date
        self.metric = metric
        self.value = value
        self.source = source
    }
}

/// Lesbare Datentypen für die Berechtigungsanfrage.
public enum HealthReadType: String, CaseIterable, Codable, Sendable {
    case workouts, heartRate, bodyMass, restingHR, hrvSDNN, sleep, respiratoryRate, wristTemperature
}

/// HealthKit verrät den Lese-Status nicht; nur, ob eine Anfrage noch aussteht.
public enum HealthAuthorizationStatus: Equatable, Sendable {
    case unavailable
    case notDetermined
    case requested
}

/// Undurchsichtiger Anker einer inkrementellen Abfrage (archivierter `HKQueryAnchor`).
public struct HealthAnchor: Equatable, Sendable {
    public var data: Data
    public init(data: Data) { self.data = data }
}

public struct HealthWorkoutChanges: Equatable, Sendable {
    public var added: [HealthWorkout]
    public var deleted: [UUID]
    public var anchor: HealthAnchor

    public init(added: [HealthWorkout], deleted: [UUID], anchor: HealthAnchor) {
        self.added = added
        self.deleted = deleted
        self.anchor = anchor
    }
}

/// `HKWorkoutActivityType.rawValue` → Name passend zu `SportClassification`. Die Rohwerte sind stabile Konstanten
/// der HealthKit-ABI; so bleibt das Mapping ohne HealthKit testbar.
public enum HealthWorkoutTypeMap {
    public static func name(forRawValue raw: UInt) -> String { table[raw] ?? "other" }

    static let table: [UInt: String] = [
        1: "americanFootball", 2: "archery", 3: "australianFootball", 4: "badminton", 5: "baseball", 6: "basketball",
        7: "bowling", 8: "boxing", 9: "climbing", 10: "cricket", 11: "crossTraining", 12: "curling", 13: "cycling",
        14: "dance", 15: "danceInspiredTraining", 16: "elliptical", 17: "equestrianSports", 18: "fencing",
        19: "fishing", 20: "functionalStrengthTraining", 21: "golf", 22: "gymnastics", 23: "handball", 24: "hiking",
        25: "hockey", 26: "hunting", 27: "lacrosse", 28: "martialArts", 29: "mindAndBody",
        30: "mixedMetabolicCardioTraining", 31: "paddleSports", 32: "play", 33: "preparationAndRecovery",
        34: "racquetball", 35: "rowing", 36: "rugby", 37: "running", 38: "sailing", 39: "skatingSports",
        40: "snowSports", 41: "soccer", 42: "softball", 43: "squash", 44: "stairClimbing", 45: "surfingSports",
        46: "swimming", 47: "tableTennis", 48: "tennis", 49: "trackAndField", 50: "traditionalStrengthTraining",
        51: "volleyball", 52: "walking", 53: "waterFitness", 54: "waterPolo", 55: "waterSports", 56: "wrestling",
        57: "yoga", 58: "barre", 59: "coreTraining", 60: "crossCountrySkiing", 61: "downhillSkiing",
        62: "flexibility", 63: "highIntensityIntervalTraining", 64: "jumpRope", 65: "kickboxing", 66: "pilates",
        67: "snowboarding", 68: "stairs", 69: "stepTraining", 70: "wheelchairWalkPace", 71: "wheelchairRunPace",
        72: "taiChi", 73: "mixedCardio", 74: "handCycling", 75: "discSports", 76: "fitnessGaming",
        77: "cardioDance", 78: "socialDance", 79: "pickleball", 80: "cooldown", 82: "swimBikeRun", 83: "transition",
        84: "underwaterDiving", 3000: "other"
    ]
}
