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

    public var proposal: PlannedWorkoutProposal {
        PlannedWorkoutProposal(date: date, definition: definition, rationale: rationale)
    }
}
