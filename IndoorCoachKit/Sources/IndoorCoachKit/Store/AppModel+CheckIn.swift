import Foundation
import SwiftData

/// Check-in vor der Einheit: speichern, heutigen Check-in lesen, gewählte Aktion protokollieren und ausführen.
extension AppModel {
    /// The first planned workout of today (nil on rest days).
    public func plannedWorkoutToday(now: Date = .now) -> StoredWorkout? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        let all = (try? context.fetch(FetchDescriptor<StoredWorkout>(sortBy: [SortDescriptor(\.date)]))) ?? []
        return all.first { !$0.isDeleted && $0.status == .planned && $0.date >= start && $0.date < end }
    }

    public func todaysCheckIn(now: Date = .now) -> StoredCheckIn? {
        let day = Calendar.current.startOfDay(for: now)
        return try? context.fetch(FetchDescriptor<StoredCheckIn>(predicate: #Predicate { $0.day == day })).first
    }

    /// True when the card/sheet should be shown: planned workout today and no check-in (or skip) yet.
    public func checkInDue(now: Date = .now) -> Bool {
        CheckIn.isDue(hasPlannedWorkoutToday: plannedWorkoutToday(now: now) != nil, alreadyAnswered: todaysCheckIn(now: now) != nil)
    }

    /// Saves today's check-in with the offers that follow from the answers. Nil if there is no planned workout or one exists already.
    @discardableResult
    public func saveCheckIn(_ answers: CheckIn.Answers, jokersAvailable: Int, now: Date = .now) -> StoredCheckIn? {
        guard let workout = plannedWorkoutToday(now: now), todaysCheckIn(now: now) == nil else { return nil }
        let definition = workout.originalDefinition ?? workout.definition
        let canSwap = ![WorkoutType.endurance, .recovery].contains(definition.type) && WorkoutSwap.base(for: definition) != nil
        let offers = CheckIn.offers(for: answers, plannedMinutes: WorkoutAdjust.minutes(definition.totalDuration),
                                    jokersAvailable: jokersAvailable, canSwap: canSwap)
        let row = StoredCheckIn(day: Calendar.current.startOfDay(for: now), answers: answers, offered: offers, createdAt: now)
        context.insert(row)
        try? context.save()
        return row
    }

    /// "Überspringen": remembered for today, no offers.
    public func skipCheckIn(now: Date = .now) {
        guard plannedWorkoutToday(now: now) != nil, todaysCheckIn(now: now) == nil else { return }
        context.insert(StoredCheckIn(day: Calendar.current.startOfDay(for: now), answers: CheckIn.Answers(), offered: [], skipped: true, createdAt: now))
        try? context.save()
    }

    /// Logs the chosen action (measure for Z1) and carries it out. The joker only confirms: the streak logic uses it
    /// automatically for a missed week.
    public func applyCheckInOffer(_ action: CheckIn.Action, to workout: StoredWorkout, now: Date = .now) async {
        todaysCheckIn(now: now)?.chosenRaw = action.raw
        try? context.save()
        switch action {
        case .shorten(let minutes, let easier): await adjust(workout, minutes: minutes, easierBy: easier)
        case .easier(let percent): await adjust(workout, minutes: nil, easierBy: percent)
        case .swapToBase: await swapToBase(workout)
        case .joker: show("Joker ist vorgemerkt. Ruh dich aus, deine Serie bleibt.", error: false)
        }
    }

    /// Replaces a planned workout by an easy Z2 ride of the same length. The true original is kept once, so
    /// `restoreOriginal` brings it back (also after an earlier "Anpassen").
    public func swapToBase(_ workout: StoredWorkout) async {
        guard workout.status == .planned, !workout.isDeleted else { return }
        let original = workout.originalDefinition ?? workout.definition
        guard let base = WorkoutSwap.base(for: original),
              let data = try? JSONEncoder().encode(base.segments) else { return }
        if workout.originalSegmentsData == nil { workout.originalSegmentsData = workout.segmentsData }
        workout.segmentsData = data
        workout.adjustmentNote = "Gegen Grundlage getauscht · Z2, \(WorkoutAdjust.minutes(base.totalDuration)) min"
        try? context.save()
        let failed = await propagateSwap(of: workout)
        if !failed { show("Gegen Grundlage getauscht.", error: false) }
    }

    /// Same best-effort follow-up as "Einheit anpassen": calendar event, then MyWhoosh replace. True if anything failed.
    private func propagateSwap(of workout: StoredWorkout) async -> Bool {
        let id = workout.persistentModelID
        var failed = false
        if let eventID = workout.calendarEventID {
            do {
                let newID = try await calendarService.upsert(eventID: eventID, title: "🚴 \(workout.title)", start: startDate(for: workout),
                                                             durationSeconds: workout.definition.totalDuration, notes: calendarNotes(for: workout))
                if let w = context.model(for: id) as? StoredWorkout, !w.isDeleted, w.calendarEventID != newID {
                    w.calendarEventID = newID
                    try? context.save()
                }
            } catch {
                Log.error(.calendar, "Tausch nicht im Kalender: \(type(of: error))")
                show(error.localizedDescription, error: true)
                failed = true
            }
        }
        if workout.myWhooshWorkoutID != nil, isMyWhooshConnected, let w = context.model(for: id) as? StoredWorkout, !w.isDeleted {
            if !failed { banner = nil }
            await sendToMyWhoosh([w])
            if banner?.isError == true { failed = true }
        }
        return failed
    }
}
