import Foundation

/// "Einheit anpassen": shorter and/or easier, undoable. Local change first; calendar and MyWhoosh follow on a best-effort basis.
extension AppModel {
    /// Adjusts a planned workout. Always derived from the original (kept once), so options can be changed again later.
    public func adjust(_ workout: StoredWorkout, minutes: Int?, easierBy: Int?) async {
        guard workout.status == .planned, !workout.isDeleted else { return }
        let base = workout.originalDefinition ?? workout.definition
        guard let result = WorkoutAdjust.apply(to: base, minutes: minutes, easierBy: easierBy),
              let data = try? JSONEncoder().encode(result.definition.segments) else { return }
        if workout.originalSegmentsData == nil { workout.originalSegmentsData = workout.segmentsData }
        workout.segmentsData = data
        // Derived from the original again, so a title/type changed by a swap goes back.
        if let originalTitle = workout.originalTitle { workout.title = originalTitle }
        if let originalTypeRaw = workout.originalTypeRaw { workout.typeRaw = originalTypeRaw }
        workout.adjustmentNote = result.description
        saveReportingErrors("Die Anpassung")
        let failed = await propagateChange(of: workout)
        if !failed { show("Einheit angepasst: \(result.description)", error: false) }
    }

    /// Puts the original segments back.
    public func restoreOriginal(_ workout: StoredWorkout) async {
        guard workout.status == .planned, !workout.isDeleted, let original = workout.originalSegmentsData else { return }
        workout.segmentsData = original
        workout.originalSegmentsData = nil
        if let originalTitle = workout.originalTitle { workout.title = originalTitle }
        if let originalTypeRaw = workout.originalTypeRaw { workout.typeRaw = originalTypeRaw }
        workout.originalTitle = nil
        workout.originalTypeRaw = nil
        workout.adjustmentNote = nil
        saveReportingErrors("Das Zurücksetzen")
        let failed = await propagateChange(of: workout)
        if !failed { show("Original wiederhergestellt.", error: false) }
    }

    /// Updates the calendar event and replaces the MyWhoosh and intervals.icu workout, if the workout was sent before.
    /// A failure keeps the local change and shows the usual error banner. Returns true if anything failed.
    func propagateChange(of workout: StoredWorkout) async -> Bool {
        let id = workout.persistentModelID
        var failed = false
        if let eventID = workout.calendarEventID {
            let request = (title: "🚴 \(workout.title)", start: startDate(for: workout),
                           duration: workout.definition.totalDuration, notes: calendarNotes(for: workout))
            do {
                let newID = try await calendarService.upsert(eventID: eventID, title: request.title, start: request.start,
                                                             durationSeconds: request.duration, notes: request.notes)
                // upsert re-creates an event deleted outside the app: keep the new id.
                if let w = context.model(for: id) as? StoredWorkout, !w.isDeleted, w.calendarEventID != newID {
                    w.calendarEventID = newID
                    try? context.save()
                }
            } catch {
                Log.error(.calendar, "Anpassung nicht im Kalender: \(type(of: error))")
                show(error.localizedDescription, error: true)
                failed = true
            }
        }
        if workout.myWhooshWorkoutID != nil, isMyWhooshConnected,
           let w = context.model(for: id) as? StoredWorkout, !w.isDeleted {
            if !failed { banner = nil }
            await sendToMyWhoosh([w]) // replaces the earlier upload and calendar task
            if banner?.isError == true { failed = true }
        }
        if workout.intervalsSentAt != nil, isIntervalsConnected,
           let w = context.model(for: id) as? StoredWorkout, !w.isDeleted {
            if !failed { banner = nil }
            await sendToIntervals([w]) // upsert replaces the calendar entry (same external_id)
            if banner?.isError == true { failed = true }
        }
        return failed
    }
}
