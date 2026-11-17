import Foundation
import SwiftData

/// G7: glue between the stored workouts and the pure `WorkoutReminder` planning.
extension AppModel {
    /// Re-registers the "30 minutes before" notifications for planned workouts (opt-in via the profile).
    /// Cheap and idempotent – called after plan accept, workout delete, app start and when the switch changes.
    public func rescheduleWorkoutReminders(now: Date = .now) async {
        guard profile.workoutReminder else { return }
        let items = ((try? context.fetch(FetchDescriptor<StoredWorkout>())) ?? []).filter { $0.status == .planned }.map {
            WorkoutReminder.Item(id: $0.id, title: $0.title, start: startDate(for: $0),
                                 duration: $0.definition.totalDuration, tss: $0.definition.estimatedTSS, status: $0.status)
        }
        await WorkoutReminder.reschedule(items: items, now: now, center: reminderCenter)
    }
}
