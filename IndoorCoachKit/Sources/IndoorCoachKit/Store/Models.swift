import Foundation
import SwiftData

@Model
public final class StoredRide {
    @Attribute(.unique) public var stravaID: Int
    public var name: String
    public var sportType: String
    public var startDate: Date
    public var movingTime: Int
    public var distance: Double
    public var averageWatts: Double?
    public var weightedAverageWatts: Double?
    public var kilojoules: Double?
    public var averageHeartrate: Double?
    public var maxHeartrate: Double?
    public var trainer: Bool
    public var isDemo: Bool
    // Added with the Winter Arc features – optional/defaulted so SwiftData migrates lightweight.
    public var perceivedExertion: Int?
    public var preferPerceivedExertion: Bool = false
    public var stravaRelativeEffort: Double?
    // Added with the power-curve feature – optional so SwiftData migrates lightweight.
    public var maxWatts: Double?
    /// Measured mean-maximal curve as JSON (see `PowerCurve.encode`); nil for rides without 1 Hz data.
    public var powerCurveData: Data?
    // Added with the aerobic-efficiency feature – optional so SwiftData migrates lightweight.
    /// Pw:HR decoupling in percent from a FIT file; nil when the ride has no 1 Hz power and heart rate.
    public var decoupling: Double?
    // Added with the abilities feature – optional so SwiftData migrates lightweight.
    /// Fatigue resistance in percent from a FIT file of at least 60 minutes; nil otherwise.
    public var durability: Double?
    // Added with the seconds-data analyses – optional so SwiftData migrates lightweight.
    /// 1 Hz power/heart rate from a FIT file (`RideSeconds` format); nil for rides without seconds data.
    @Attribute(.externalStorage) public var secondsData: Data?
    // Added with the Apple-Health workouts (W3-B) – all optional so SwiftData migrates lightweight.
    /// Herkunft, wenn nicht Strava/MyWhoosh/FIT: `"appleHealth"` (`StoredRide.healthSource`).
    public var sourceRaw: String?
    /// Health-Workout (UUID), das diese Fahrt ist; wird beim Löschen in Health mitgelöscht.
    public var healthUUID: String?
    /// Geschätzte TSS einer aeroben Fremdsportart (O6); nil bei allen anderen Fahrten.
    public var estimatedTSS: Double?
    /// HealthKit-Sportart einer aeroben Fremdsportart (z. B. `running`); nil bei Radfahrten.
    public var foreignSport: String?
    /// Health-Workout, das mit dieser Fahrt zusammengeführt wurde (rückgängig machbar).
    public var mergedHealthUUID: String?
    /// Sichtbarer Hinweis zur Zusammenführung.
    public var healthNote: String?

    public static let healthSource = "appleHealth"

    public init(_ r: RideSummary, isDemo: Bool = false) {
        stravaID = r.id
        name = r.name
        sportType = r.sportType
        startDate = r.startDate
        movingTime = r.movingTime
        distance = r.distance
        averageWatts = r.averageWatts
        weightedAverageWatts = r.weightedAverageWatts
        kilojoules = r.kilojoules
        averageHeartrate = r.averageHeartrate
        maxHeartrate = r.maxHeartrate
        trainer = r.trainer
        self.isDemo = isDemo
        perceivedExertion = r.perceivedExertion
        preferPerceivedExertion = r.preferPerceivedExertion
        stravaRelativeEffort = r.stravaRelativeEffort
        maxWatts = r.maxWatts
        powerCurveData = r.powerCurve.flatMap(PowerCurve.encode)
        decoupling = r.decoupling
        durability = r.durability
        if let uuid = r.healthUUID {
            sourceRaw = Self.healthSource
            healthUUID = uuid
            foreignSport = r.foreignSport
            estimatedTSS = r.estimatedTSS
        }
    }

    public func update(from r: RideSummary) {
        name = r.name
        sportType = r.sportType
        startDate = r.startDate
        movingTime = r.movingTime
        distance = r.distance
        averageWatts = r.averageWatts
        weightedAverageWatts = r.weightedAverageWatts
        kilojoules = r.kilojoules
        averageHeartrate = r.averageHeartrate
        maxHeartrate = r.maxHeartrate
        trainer = r.trainer
        // Strava's value is refreshed; the athlete's own PE is local and survives every sync.
        stravaRelativeEffort = r.stravaRelativeEffort
        // A summary-only sync (Strava) must not wipe a curve measured from a FIT file, nor a known max.
        if let max = r.maxWatts { maxWatts = max }
        if let curve = r.powerCurve, let data = PowerCurve.encode(curve) { powerCurveData = data }
        if let d = r.decoupling { decoupling = d }
        if let d = r.durability { durability = d }
    }

    public var powerCurve: [Int: Double]? { PowerCurve.decode(powerCurveData) }

    public var summary: RideSummary {
        var r = RideSummary(id: stravaID, name: name, sportType: sportType, startDate: startDate, movingTime: movingTime,
                            distance: distance, averageWatts: averageWatts, weightedAverageWatts: weightedAverageWatts,
                            kilojoules: kilojoules, averageHeartrate: averageHeartrate, maxHeartrate: maxHeartrate, trainer: trainer)
        r.perceivedExertion = perceivedExertion
        r.preferPerceivedExertion = preferPerceivedExertion
        r.stravaRelativeEffort = stravaRelativeEffort
        r.maxWatts = maxWatts
        r.powerCurve = powerCurve
        r.decoupling = decoupling
        r.durability = durability
        r.healthUUID = healthUUID
        r.foreignSport = foreignSport
        r.estimatedTSS = estimatedTSS
        r.healthNote = healthNote
        return r
    }
}

public enum WorkoutStatus: String, Codable, CaseIterable, Sendable {
    case planned, done, skipped

    public var label: String {
        switch self {
        case .planned: "Geplant"
        case .done: "Erledigt"
        case .skipped: "Ausgelassen"
        }
    }

    public var symbol: String {
        switch self {
        case .planned: "calendar"
        case .done: "checkmark.circle.fill"
        case .skipped: "xmark.circle"
        }
    }
}

public enum WorkoutSource: String, Codable, Sendable {
    case claude, demo, manual
}

@Model
public final class StoredWorkout {
    @Attribute(.unique) public var id: UUID
    public var date: Date
    public var title: String
    public var typeRaw: String
    public var summary: String
    public var rationale: String
    public var segmentsData: Data
    public var statusRaw: String
    public var calendarEventID: String?
    public var linkedRideID: Int?
    public var sourceRaw: String
    public var weekFocus: String?
    public var createdAt: Date
    // MyWhoosh direct upload (B21) – optional for lightweight migration.
    public var myWhooshWorkoutID: String?
    public var myWhooshTaskID: String?
    public var myWhooshSentAt: Date?
    // intervals.icu: Zeitpunkt des letzten Sendens (nil = nie gesendet) – optional für leichte Migration. Der Termin dort
    // trägt die UUID dieser Einheit als `external_id`.
    public var intervalsSentAt: Date?
    // "Einheit anpassen" – optional for lightweight migration. The original segments are kept once, so the change can be undone.
    public var originalSegmentsData: Data?
    public var adjustmentNote: String?
    // "Gegen Grundlage tauschen" – optional for lightweight migration: original title and type, kept once like the segments.
    public var originalTitle: String?
    public var originalTypeRaw: String?

    public init(proposal: PlannedWorkoutProposal, source: WorkoutSource, weekFocus: String?) {
        id = UUID()
        date = proposal.date
        title = proposal.definition.title
        typeRaw = proposal.definition.type.rawValue
        summary = proposal.definition.summary
        rationale = proposal.rationale
        segmentsData = (try? JSONEncoder().encode(proposal.definition.segments)) ?? Data()
        statusRaw = WorkoutStatus.planned.rawValue
        sourceRaw = source.rawValue
        self.weekFocus = weekFocus
        createdAt = .now
    }

    public var type: WorkoutType { WorkoutType(rawValue: typeRaw) ?? .mixed }

    public var status: WorkoutStatus {
        get { WorkoutStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }

    public var source: WorkoutSource { WorkoutSource(rawValue: sourceRaw) ?? .manual }

    public var definition: WorkoutDefinition {
        let segments = (try? JSONDecoder().decode([Segment].self, from: segmentsData)) ?? []
        return WorkoutDefinition(title: title, type: type, summary: summary, segments: segments)
    }

    /// The workout as originally planned (before "Anpassen"), nil if it was never adjusted.
    public var originalDefinition: WorkoutDefinition? {
        guard let originalSegmentsData, let segments = try? JSONDecoder().decode([Segment].self, from: originalSegmentsData) else { return nil }
        let originalType = originalTypeRaw.flatMap(WorkoutType.init(rawValue:)) ?? type
        return WorkoutDefinition(title: originalTitle ?? title, type: originalType, summary: summary, segments: segments)
    }

    public var proposal: PlannedWorkoutProposal {
        PlannedWorkoutProposal(date: date, definition: definition, rationale: rationale)
    }
}
