import Foundation
import SwiftData

/// Gemerktes Ergebnis des Highlight-Slots und der Joker-Woche: höchstens eine Berechnung je Fingerabdruck, nicht je Heute-Redraw.
@MainActor
final class ComebackMemo {
    var highlightKey: Int?
    var highlight: Comeback.Highlight?
    var jokerKey: Int?
    var jokerWeek: Date?
    /// Tests: wie oft wirklich gerechnet wurde.
    var computations = 0

    func reset() { highlightKey = nil; jokerKey = nil; highlight = nil; jokerWeek = nil }
}

/// Willkommen zurück und „Dein Warum“ (docs/22, B4): letzte Aktivität quellenübergreifend, Joker-Woche der Pause,
/// Speichern des Satzes, die lockere Einheit ohne Plan. Alles lokal; der Satz geht nie an Claude.
extension AppModel {
    // MARK: Letzte Aktivität

    /// Beginn der jüngsten Einheit über alle Quellen: Fahrten (MyWhoosh, intervals.icu, Brücke, FIT, Strava, Aufzeichnung, Health
    /// inklusive Fremdsport) sowie Kraft und andere Einheiten. nil, wenn es noch nichts gibt.
    public func lastActivityDate(rides: [RideSummary]) -> Date? {
        (rides.map(\.startDate) + strengthActivityDates()).max()
    }

    /// `.returning`, wenn die letzte Aktivität mindestens 10 Kalendertage zurückliegt (`now` = `AppModel.today`).
    public func comebackState(rides: [RideSummary], now: Date = AppModel.today, calendar: Calendar = .current) -> Comeback.State {
        Comeback.state(lastActivity: lastActivityDate(rides: rides), now: now, calendar: calendar)
    }

    /// Montag der jüngsten Woche seit der letzten Aktivität, die ein Joker aufgefangen hat; nil ohne eine solche Woche.
    func comebackJokerWeek(rides: [RideSummary], lastActivity: Date?, now: Date, calendar: Calendar = .current) -> Date? {
        guard let lastActivity else { return nil }
        let since = Consistency.weekStart(of: lastActivity, calendar: calendar)
        return consistency(rides: rides, now: now).weeks.last { $0.state == .joker && $0.start >= since }?.start
    }

    /// Wie `comebackJokerWeek(rides:lastActivity:now:)`, aber mit der jüngsten Aktivität aus dem Speicher und nur einmal je Fingerabdruck.
    func comebackJokerWeek(rides: [RideSummary], now: Date, calendar: Calendar = .current) -> Date? {
        let key = activityFingerprint(rideCount: rides.count, newestRide: rides.map(\.startDate).max(), now: now)
        if comebackMemo.jokerKey == key { return comebackMemo.jokerWeek }
        comebackMemo.computations += 1
        let week = comebackJokerWeek(rides: rides, lastActivity: lastActivityDate(rides: rides), now: now, calendar: calendar)
        comebackMemo.jokerKey = key
        comebackMemo.jokerWeek = week
        return week
    }

    /// Was im Highlight-Slot auf Heute vor Wochenrückblick und Challenge steht: Willkommen zurück oder die einmalige Warum-Frage.
    /// Das Ergebnis wird je Fingerabdruck (Fahrten, Kraft, Pläne, Tag, Schalter) nur einmal berechnet.
    public func winterHighlight(rides: [RideSummary], dismissedDay: String?, whyPromptDismissed: Bool,
                                now: Date = AppModel.today, calendar: Calendar = .current) -> Comeback.Highlight? {
        var hasher = Hasher()
        hasher.combine(activityFingerprint(rideCount: rides.count, newestRide: rides.map(\.startDate).max(), now: now))
        hasher.combine(dismissedDay)
        hasher.combine(whyPromptDismissed)
        hasher.combine(whyNote)
        let key = hasher.finalize()
        if comebackMemo.highlightKey == key { return comebackMemo.highlight }
        comebackMemo.computations += 1
        let value = computeWinterHighlight(rides: rides, dismissedDay: dismissedDay, whyPromptDismissed: whyPromptDismissed,
                                           now: now, calendar: calendar)
        comebackMemo.highlightKey = key
        comebackMemo.highlight = value
        return value
    }

    private func computeWinterHighlight(rides: [RideSummary], dismissedDay: String?, whyPromptDismissed: Bool,
                                        now: Date, calendar: Calendar) -> Comeback.Highlight? {
        guard let arc = winterArc(rides: rides, now: now) else { return nil }
        let day = calendar.startOfDay(for: now)
        let active = day >= arc.start && day <= arc.goal
        let rode = rides.contains { $0.startDate >= arc.start }
        return Comeback.highlight(state: comebackState(rides: rides, now: now, calendar: calendar), today: now,
                                  dismissedDay: dismissedDay, whyNote: whyNote, whyPromptDismissed: whyPromptDismissed,
                                  rodeThisSeason: rode, arcActive: active, calendar: calendar)
    }

    // MARK: Postkarten

    /// Die zehn Karten für den Stand des Winter Arc; das Ankunftsdatum kommt aus `Trophies.levelDates` (keine neue Speicherung).
    public func postcards(rides: [RideSummary], status: WinterArc.Status) -> [Postcard] {
        let dates = Trophies.levelDates(status: status, points: fitnessSeries(rides: rides).points)
        return Postcards.all(level: status.level.number, levelProgress: status.levelProgress, levelDates: dates)
    }

    // MARK: Dein Warum

    /// Der Tag, an dem der Satz geschrieben wurde („Dein Satz vom 4. November“); nil ohne Satz.
    public var whyNoteSavedOn: Date? {
        guard whyNote != nil, let seconds = defaults.object(forKey: WhyNote.savedOnKey) as? Double else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Speichert den Satz getrimmt und auf 140 Zeichen gekürzt; leer löscht ihn. Der Tag bleibt, solange die Worte bleiben.
    public func saveWhy(_ raw: String?, on day: Date = AppModel.today) {
        let normalized = WhyNote.normalize(raw)
        guard let normalized else {
            defaults.removeObject(forKey: WhyNote.savedOnKey)
            whyNote = nil
            return
        }
        if normalized != whyNote || defaults.object(forKey: WhyNote.savedOnKey) == nil {
            defaults.set(day.timeIntervalSince1970, forKey: WhyNote.savedOnKey)
        }
        whyNote = normalized
        defaults.set(true, forKey: WhyNote.promptDismissedKey)   // die einmalige Frage ist beantwortet
    }

    // MARK: Lockerer Einstieg ohne Plan

    /// „Grundlage 30 min“ für heute: legt die Einheit an (oder liefert die vom selben Tag), damit „Senden“ und „Export“ wie gewohnt
    /// funktionieren. Läuft ohne Verbindung und ohne Claude.
    @discardableResult
    public func createEasyReturnWorkout(now: Date = AppModel.today, calendar: Calendar = .current) -> StoredWorkout? {
        let day = calendar.startOfDay(for: now)
        let definition = Comeback.easyRide()
        let existing = ((try? context.fetch(FetchDescriptor<StoredWorkout>())) ?? []).first {
            $0.status == .planned && calendar.isDate($0.date, inSameDayAs: day) && $0.title == definition.title && $0.source == .manual
        }
        if let existing { return existing }
        let proposal = PlannedWorkoutProposal(date: day, definition: definition,
                                              rationale: "Lockerer Wiedereinstieg nach der Pause: Die ersten Einheiten dürfen ruhig locker sein.")
        let workout = StoredWorkout(proposal: proposal, source: .manual, weekFocus: nil)
        context.insert(workout)
        guard saveReportingErrors("Die Einheit") else { return nil }
        return workout
    }
}
