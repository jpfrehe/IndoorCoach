import Foundation
import SwiftData

/// In-process cache of compliance results (key: workout, ride, FTP and the plan's segments).
final class ComplianceCache: @unchecked Sendable {
    struct Key: Hashable {
        var workout: UUID
        var ride: Int
        var ftp: Int
        var segments: Data
    }

    static let shared = ComplianceCache()
    private let lock = NSLock()
    private var storage: [Key: IntervalCompliance.Result] = [:]

    func value(for key: Key) -> IntervalCompliance.Result? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    func store(_ result: IntervalCompliance.Result, for key: Key) {
        lock.lock(); defer { lock.unlock() }
        if storage.count > 64 { storage.removeAll() }
        storage[key] = result
    }
}

extension AppModel {
    /// Planned vs. actual for a finished workout whose linked ride has stored seconds; nil otherwise.
    public func intervalCompliance(for workout: StoredWorkout) -> IntervalCompliance.Result? {
        guard workout.status == .done, let rideID = workout.linkedRideID else { return nil }
        let key = ComplianceCache.Key(workout: workout.id, ride: rideID, ftp: profile.ftp, segments: workout.segmentsData)
        if let cached = ComplianceCache.shared.value(for: key) { return cached }
        // ANCHOR-REC: no planned-vs-actual from assumed watts (pulse-only recordings have no power seconds).
        guard let seconds = rideSeconds(id: rideID), RecordingMerge.hasPower(seconds),
              let result = IntervalCompliance.analyze(definition: workout.definition, seconds: seconds, ftp: profile.ftp)
        else { return nil }
        ComplianceCache.shared.store(result, for: key)
        return result
    }
}

#if DEBUG
extension AppModel {
    /// Launch argument `-uiComplianceSeed YES`: call after `bootstrap()` (demo rides must exist).
    func applyComplianceSeed() {
        guard UserDefaults.standard.bool(forKey: "uiComplianceSeed") else { return }
        seedComplianceWorkout()
    }

    /// Ensures one done workout "Sweet Spot 2×20" linked to the newest demo indoor ride named "…2×20", whose seconds
    /// follow the same structure. Idempotent. Returns false when no such ride exists.
    @discardableResult
    func seedComplianceWorkout() -> Bool {
        let descriptor = FetchDescriptor<StoredRide>(predicate: #Predicate { $0.isDemo && $0.trainer && $0.name.contains("2×20") },
                                                     sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        // The demo ride lasts 52–68 min depending on the calendar day; both 20-min blocks only fit before the 8-min
        // cool-down from 63 min on (10 + 20 + 5 + 20 + 8). Pick the most recent ride that is long enough.
        let minimum = 600 + 2 * 1500 - 300 + 480
        guard let ride = (try? context.fetch(descriptor))?.first(where: { $0.movingTime >= minimum }) else { return false }
        if ride.secondsData == nil {
            ride.secondsData = DemoData.syntheticSeconds(for: ride.summary, ftp: profile.ftp).encoded()
        }
        let rideID = ride.stravaID
        let title = "Sweet Spot 2×20"
        let existing = (try? context.fetch(FetchDescriptor<StoredWorkout>(predicate: #Predicate { $0.title == title && $0.linkedRideID == rideID })))?.first
        if let existing {
            existing.status = .done
        } else {
            let remainder = max(0, ride.movingTime - 600 - 2 * 1500 - 480)
            var segments: [Segment] = [.warmup(10, from: 0.5, to: 0.7),
                                       .intervals(2, on: 1200, at: 0.9, off: 300, at: 0.55)]
            if remainder >= 60 { segments.append(Segment(kind: .steady, duration: remainder, power: 0.55)) }
            segments.append(.cooldown(8, from: 0.6, to: 0.4))
            let definition = WorkoutDefinition(title: title, type: .sweetSpot, summary: "Zwei Blöcke à 20 Minuten im Sweet Spot.",
                                               segments: segments)
            let day = Calendar.current.startOfDay(for: ride.startDate)
            let workout = StoredWorkout(proposal: PlannedWorkoutProposal(date: day, definition: definition, rationale: "Demo"),
                                        source: .demo, weekFocus: nil)
            workout.status = .done
            workout.linkedRideID = rideID
            context.insert(workout)
        }
        try? context.save()
        return true
    }
}
#endif
