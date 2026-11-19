import Foundation

// Regeln für den Health-Export eigener Einheiten (docs/17 §8.4, B51). Opt-in, Standard aus. Pur, ohne HealthKit.
// Geschrieben wird nur: Workout (Typ, Beginn, Ende) und Pulswerte. Nie Leistung und nie angenommene Watt.

/// Sportarten, die je einzeln für den Export freigeschaltet werden.
public enum HealthExportSport: String, Codable, CaseIterable, Sendable {
    case strength, other, cycling

    public var title: String {
        switch self {
        case .strength: "Kraft"
        case .other: "Andere Einheiten"
        case .cycling: "Rad-Aufzeichnung"
        }
    }
}

/// Schreibrechte, die IndoorCoach höchstens anfragt.
public enum HealthWriteType: String, Hashable, Sendable {
    case workout, heartRate
}

public struct HealthExportSettings: Codable, Equatable, Sendable {
    public var strength: Bool
    public var other: Bool
    public var cycling: Bool

    public init(strength: Bool = false, other: Bool = false, cycling: Bool = false) {
        self.strength = strength
        self.other = other
        self.cycling = cycling
    }

    public func isEnabled(_ sport: HealthExportSport) -> Bool {
        switch sport {
        case .strength: strength
        case .other: other
        case .cycling: cycling
        }
    }

    public mutating func set(_ sport: HealthExportSport, _ on: Bool) {
        switch sport {
        case .strength: strength = on
        case .other: other = on
        case .cycling: cycling = on
        }
    }

    public var anyEnabled: Bool { strength || other || cycling }
}

/// Eine eigene Aufzeichnung, reduziert auf das, was der Export braucht. Bewusst ohne Leistungsfelder.
public struct HealthExportCandidate: Equatable, Sendable {
    public var id: UUID
    public var sport: HealthExportSport
    /// Nur bei „Andere Einheit“: Sportart (Namen wie `HealthWorkoutTypeMap`); sonst nil.
    public var activityTypeName: String?
    public var start: Date
    public var end: Date
    /// Puls pro Sekunde ab `start`, 0 = Lücke.
    public var heartRate: [UInt8]?

    public init(id: UUID, sport: HealthExportSport, activityTypeName: String?, start: Date, end: Date, heartRate: [UInt8]?) {
        self.id = id
        self.sport = sport
        self.activityTypeName = activityTypeName
        self.start = start
        self.end = end
        self.heartRate = heartRate
    }
}

public struct HealthExportPayload: Equatable, Sendable {
    public struct HeartSample: Equatable, Sendable {
        public var date: Date
        public var bpm: Double
    }

    public var id: UUID
    public var activityTypeName: String
    public var start: Date
    public var end: Date
    public var heartRate: [HeartSample]
}

public enum HealthExportRules {
    public enum Decision: Equatable, Sendable {
        case export, disabled, overlaps, tooShort
    }

    /// Ab diesem Anteil Überlappung mit dem Workout einer anderen Quelle wird nicht exportiert.
    public static let overlapShare = 0.5
    public static let minimumSeconds: TimeInterval = 60

    public static func decide(_ candidate: HealthExportCandidate, settings: HealthExportSettings,
                              existing: [HealthWorkout]) -> Decision {
        guard settings.isEnabled(candidate.sport) else { return .disabled }
        let duration = candidate.end.timeIntervalSince(candidate.start)
        guard duration >= minimumSeconds else { return .tooShort }
        // Eigene, früher exportierte Workouts zählen nicht als „andere Quelle“.
        let overlap = existing.filter { !$0.isOwnSource }.reduce(0.0) {
            $0 + max(0, min(candidate.end, $1.end).timeIntervalSince(max(candidate.start, $1.start)))
        }
        return overlap / duration >= overlapShare ? .overlaps : .export
    }

    /// Nur diese Typen werden angefragt – und nur, wenn mindestens eine Sportart eingeschaltet ist.
    public static func writeTypes(for settings: HealthExportSettings) -> Set<HealthWriteType> {
        settings.anyEnabled ? [.workout, .heartRate] : []
    }

    public static func payload(for candidate: HealthExportCandidate) -> HealthExportPayload {
        let name: String
        switch candidate.sport {
        case .strength: name = "traditionalStrengthTraining"
        case .cycling: name = "cycling"
        case .other: name = candidate.activityTypeName ?? "other"
        }
        let samples = (candidate.heartRate ?? []).enumerated().compactMap { index, bpm -> HealthExportPayload.HeartSample? in
            bpm > 0 ? .init(date: candidate.start.addingTimeInterval(Double(index)), bpm: Double(bpm)) : nil
        }
        return HealthExportPayload(id: candidate.id, activityTypeName: name, start: candidate.start, end: candidate.end, heartRate: samples)
    }
}
