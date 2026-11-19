import Foundation
import SwiftData

/// Result of handing a finished recording to the ride store.
public enum RecordingOutcome: Equatable, Sendable {
    /// Pulse track hung on this ride (`StoredRide.stravaID`).
    case attached(rideID: Int)
    /// No ride yet: the recording waits and is matched on the next import.
    case pending
    /// Strength / other recordings are not rides (the consumer of that kind handles them).
    case notRide
}

/// Where the power of a ride with an attached recording comes from.
public enum RecordingPowerSource: String, Codable, Sendable {
    /// Real power seconds exist (bridge / FIT); the iPhone only added pulse.
    case measured
    /// Pulse only: the trainer is assumed to have held the plan in ERG mode.
    case assumedERG

    public var label: String {
        switch self {
        case .measured: "gemessen, Puls vom iPhone ergänzt"
        case .assumedERG: "angenommen (ERG)"
        }
    }
}

/// Ziel einer beendeten Aufzeichnung je `RecordingKind`.
public enum RecordingHandoff: Equatable, Sendable {
    case merged(RecordingOutcome)
    case finishSheet
}

/// Which recording hangs on which ride (kept in the defaults, no schema change).
struct RecordingAttachment: Codable, Equatable, Sendable {
    var recordingID: UUID
    var rideID: Int
    var plannedWorkoutID: UUID?
    /// Seconds the pulse track was shifted against the recording start (base + fine + manual).
    var shift: Int
    var gapSeconds: Int
    var reconnects: Int
}

extension AppModel {
    /// Recordings that wait for their ride (older than two weeks are dropped when matching).
    public var pendingRecordings: [StoredRecording] {
        get { Self.decodeJSON([StoredRecording].self, defaults.data(forKey: Keys.recordingPending)) ?? [] }
        set {
            if newValue.isEmpty { defaults.removeObject(forKey: Keys.recordingPending) } else {
                defaults.set(Self.encodeJSON(newValue), forKey: Keys.recordingPending)
            }
        }
    }

    var recordingAttachments: [Int: RecordingAttachment] {
        get {
            let list = Self.decodeJSON([RecordingAttachment].self, defaults.data(forKey: Keys.recordingAttached)) ?? []
            return Dictionary(list.map { ($0.rideID, $0) }, uniquingKeysWith: { _, last in last })
        }
        set { defaults.set(Self.encodeJSON(Array(newValue.values)), forKey: Keys.recordingAttached) }
    }

    func recordingAttachment(for ride: RideSummary) -> RecordingAttachment? { recordingAttachments[ride.id] }

    /// Power source label of a ride that carries an iPhone recording; nil for every other ride.
    public func recordingSource(for ride: RideSummary) -> RecordingPowerSource? {
        guard recordingAttachments[ride.id] != nil else { return nil }
        guard let seconds = rideSeconds(id: ride.id) else { return .assumedERG }
        return RecordingMerge.hasPower(seconds) ? .measured : .assumedERG
    }

    /// Hands a stopped recording to the store: a ride recording is hung on the matching ride (same day, start ±30 min,
    /// similar duration) or waits for it. `manualShift` moves the pulse track by that many seconds (positive = the
    /// track is read later).
    @discardableResult
    public func finishRecording(_ result: RecordingResult, manualShift: Int = 0) -> RecordingOutcome {
        guard result.kind == .ride else { return .notRide }
        let recording = StoredRecording(result)
        if let ride = RecordingMerge.bestMatch(for: recording, in: allRides()), attach(recording, to: ride, manualShift: manualShift) {
            return .attached(rideID: ride.id)
        }
        pendingRecordings = pendingRecordings.filter { $0.id != recording.id } + [recording]
        Log.notice(.sync, "Aufzeichnung wartet auf eine Fahrt (\(recording.heartRate.count) s)")
        return .pending
    }

    /// Was nach dem Stopp passiert: Rad geht in den Merge-Weg, Kraft und „Andere Einheit“ brauchen erst das
    /// Abschluss-Sheet (Härte, Beine) und werden danach mit `saveStrength(from:draft:)` gespeichert.
    @discardableResult
    public func handOff(_ result: RecordingResult) -> RecordingHandoff {
        result.kind == .ride ? .merged(finishRecording(result)) : .finishSheet
    }

    /// Called after every import: attaches waiting recordings to rides that arrived since.
    func matchPendingRecordings() {
        let pending = pendingRecordings
        guard !pending.isEmpty else { return }
        let rides = allRides()
        var remaining: [StoredRecording] = []
        for recording in pending {
            if let ride = RecordingMerge.bestMatch(for: recording, in: rides), attach(recording, to: ride, manualShift: 0) {
                continue
            }
            if Date.now.timeIntervalSince(recording.endedAt) < 14 * 86_400 { remaining.append(recording) }
        }
        pendingRecordings = remaining
    }

    /// Seconds to store when `incoming` (bridge / FIT) arrives for `row`; nil = keep what the ride has.
    func upgradedSeconds(_ incoming: RideSeconds, over row: StoredRide) -> RideSeconds? {
        RecordingMerge.upgrade(existing: RideSeconds.decode(row.secondsData), incoming: incoming)
    }

    /// Definition of a planned workout (for the result view of a recording).
    func workoutDefinition(id: UUID) -> WorkoutDefinition? {
        var d = FetchDescriptor<StoredWorkout>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first?.definition
    }

    // MARK: Attach

    private func attach(_ recording: StoredRecording, to ride: RideSummary, manualShift: Int) -> Bool {
        let rideID = ride.id
        var descriptor = FetchDescriptor<StoredRide>(predicate: #Predicate { $0.stravaID == rideID })
        descriptor.fetchLimit = 1
        guard let row = (try? context.fetch(descriptor))?.first else { return false }
        let existing = RideSeconds.decode(row.secondsData)
        let length = min(max(existing?.count ?? ride.movingTime, 1), FITParser.maxSeriesSeconds)

        let workout = recording.plannedWorkoutID.flatMap { id -> StoredWorkout? in
            var d = FetchDescriptor<StoredWorkout>(predicate: #Predicate { $0.id == id })
            d.fetchLimit = 1
            return (try? context.fetch(d))?.first
        }
        let hr = recording.heartRateSeconds
        let base = RecordingMerge.baseShift(recording: recording, rideStart: ride.startDate)
        var fine = 0
        if let definition = recording.definition ?? workout?.definition,
           let expected = IntervalCompliance.workBlocks(definition).first?.start {
            fine = RecordingMerge.fineShift(hr: RecordingMerge.align(hr, shift: base, length: length), expectedRiseAt: expected)
        }
        let shift = base + fine + manualShift
        let aligned = RecordingMerge.align(hr, shift: shift, length: length)
        guard aligned.contains(where: { $0 > 0 }) else { return false }

        let merged = RecordingMerge.merge(existing: existing, heartRate: aligned)
        row.secondsData = merged.encoded()
        let valid = (merged.heartRate ?? []).filter { $0 > 0 }
        if row.averageHeartrate == nil, !valid.isEmpty {
            row.averageHeartrate = Double(valid.reduce(0) { $0 + Int($1) }) / Double(valid.count)
        }
        if row.maxHeartrate == nil, let top = valid.max() { row.maxHeartrate = Double(top) }
        if let workout, workout.linkedRideID == nil {
            workout.linkedRideID = ride.id
            workout.status = .done
        }
        var attachments = recordingAttachments
        attachments[ride.id] = RecordingAttachment(recordingID: recording.id, rideID: ride.id,
                                                   plannedWorkoutID: recording.plannedWorkoutID, shift: shift,
                                                   gapSeconds: recording.gapSeconds, reconnects: recording.reconnects)
        recordingAttachments = attachments
        try? context.save()
        invalidateSecondsDigests()
        Log.notice(.sync, "Aufzeichnung an Fahrt gehängt (Versatz \(shift) s, Lücken \(recording.gapSeconds) s)")
        exportToHealth(recording)   // nur wenn „Rad-Aufzeichnung“ eingeschaltet ist
        return true
    }

    // MARK: JSON helpers

    private static func encodeJSON<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(value)
    }

    private static func decodeJSON<T: Decodable>(_ type: T.Type, _ data: Data?) -> T? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }
}
