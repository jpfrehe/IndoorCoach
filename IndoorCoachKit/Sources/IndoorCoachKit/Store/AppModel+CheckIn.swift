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
        guard saveReportingErrors("Der Check-in") else { return nil }
        return row
    }

    /// "Überspringen": remembered for today, no offers.
    public func skipCheckIn(now: Date = .now) {
        guard plannedWorkoutToday(now: now) != nil, todaysCheckIn(now: now) == nil else { return }
        context.insert(StoredCheckIn(day: Calendar.current.startOfDay(for: now), answers: CheckIn.Answers(), offered: [], skipped: true, createdAt: now))
        saveReportingErrors("Der Check-in")
    }

    /// Logs the chosen action (measure for Z1) and carries it out. The joker is spent for the current week
    /// (`useJoker`, needs the rides for the streak evaluation).
    public func applyCheckInOffer(_ action: CheckIn.Action, to workout: StoredWorkout, rides: [RideSummary] = [],
                                  now: Date = .now) async {
        todaysCheckIn(now: now)?.chosenRaw = action.raw
        try? context.save()
        switch action {
        case .shorten(let minutes, let easier): await adjust(workout, minutes: minutes, easierBy: easier)
        case .easier(let percent): await adjust(workout, minutes: nil, easierBy: percent)
        case .swapToBase: await swapToBase(workout)
        case .joker:
            if useJoker(rides: rides, now: now) {
                show("Joker eingesetzt. Ruh dich aus, deine Serie bleibt.", error: false)
            } else {
                show("Kein Joker verfügbar.", error: true)
            }
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
        if workout.originalTitle == nil {
            workout.originalTitle = workout.title
            workout.originalTypeRaw = workout.typeRaw
        }
        workout.segmentsData = data
        workout.title = "Grundlage \(WorkoutAdjust.minutes(base.totalDuration)) min (getauscht)"
        workout.typeRaw = base.type.rawValue
        workout.adjustmentNote = "Gegen Grundlage getauscht · Z2, \(WorkoutAdjust.minutes(base.totalDuration)) min"
        saveReportingErrors("Der Tausch")
        let failed = await propagateChange(of: workout)
        if !failed { show("Gegen Grundlage getauscht.", error: false) }
    }
}
