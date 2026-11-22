import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

/// Willkommen zurück (docs/22, B4): Grenze 10 Tage, Zeitzonen, Landmarken, Texte ohne Urteil, Startaktion, Highlight-Slot.
@Suite("Willkommen zurück · Logik")
struct ComebackTests {
    private func calendar(_ zone: String = "Europe/Berlin") -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        return c
    }

    private func at(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12, minute: Int = 0, in c: Calendar) -> Date {
        c.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute))!
    }

    /// Wörter, die in keinem Text der Rückkehr stehen dürfen (docs/22, Tonregeln).
    static let forbidden = ["verpasst", "gesunken", "verloren", "Rückstand", "Versagen", "Strafe", "faul", "schwach", "leider", "endlich"]

    // MARK: Grenze (Akzeptanz 1)

    @Test func nineDaysIsNoComebackTenDaysIs() {
        let c = calendar()
        let now = at(2026, 12, 20, in: c)
        #expect(Comeback.state(lastActivity: at(2026, 12, 11, in: c), now: now, calendar: c) == .none)
        #expect(Comeback.state(lastActivity: at(2026, 12, 10, in: c), now: now, calendar: c) == .returning(days: 10, landmark: nil))
        #expect(Comeback.state(lastActivity: at(2026, 12, 1, in: c), now: now, calendar: c) == .returning(days: 19, landmark: nil))
    }

    @Test func daysAreCalendarDaysNotHours() {
        let c = calendar()
        // 23:50 am 10.12. und 00:10 am 20.12.: nur 9 Tage und 20 Minuten, aber 10 Kalendertage.
        #expect(Comeback.state(lastActivity: at(2026, 12, 10, hour: 23, minute: 50, in: c), now: at(2026, 12, 20, hour: 0, minute: 10, in: c),
                               calendar: c) == .returning(days: 10, landmark: nil))
        // 00:10 am 10.12. und 23:50 am 19.12.: 9 Tage und 23 Stunden = 9 Kalendertage.
        #expect(Comeback.state(lastActivity: at(2026, 12, 10, hour: 0, minute: 10, in: c), now: at(2026, 12, 19, hour: 23, minute: 50, in: c),
                               calendar: c) == .none)
    }

    @Test func theLocalZoneDecidesWhereTheDayEnds() {
        // Letzte Aktivität 10.12., 22:30 UTC (Berlin: 10.12., 23:30); jetzt 20.12., 00:30 UTC (Berlin: 20.12., 01:30) = 10 Kalendertage.
        // In New York (UTC−5) sind es 10.12., 17:30 bis 19.12., 19:30 = 9 Kalendertage.
        let utc = calendar("UTC")
        let last = at(2026, 12, 10, hour: 22, minute: 30, in: utc)
        let now = at(2026, 12, 20, hour: 0, minute: 30, in: utc)
        #expect(Comeback.state(lastActivity: last, now: now, calendar: calendar("Europe/Berlin")) == .returning(days: 10, landmark: nil))
        #expect(Comeback.state(lastActivity: last, now: now, calendar: calendar("America/New_York")) == .none)
    }

    @Test func noActivityAtAllIsNotAComeback() {
        let c = calendar()
        #expect(Comeback.state(lastActivity: nil, now: at(2026, 12, 20, in: c), calendar: c) == .none)
    }

    @Test func aFutureActivityIsNeverAComeback() {
        let c = calendar()
        #expect(Comeback.state(lastActivity: at(2027, 1, 5, in: c), now: at(2026, 12, 20, in: c), calendar: c) == .none)
    }

    // MARK: Landmarken (Akzeptanz 7)

    @Test func mondayFirstOfMonthAndNewYearAreLandmarks() {
        let c = calendar()
        let last = at(2026, 12, 1, in: c)
        // Montag, 21.12.2026
        #expect(Comeback.state(lastActivity: last, now: at(2026, 12, 21, in: c), calendar: c) == .returning(days: 20, landmark: .newWeek))
        // Freitag, 1.1.2027 → Neujahr (nicht Monatserster)
        #expect(Comeback.state(lastActivity: last, now: at(2027, 1, 1, in: c), calendar: c) == .returning(days: 31, landmark: .newYear))
        // Montag, 1.2.2027 → Monatserster schlägt Montag
        #expect(Comeback.state(lastActivity: last, now: at(2027, 2, 1, in: c), calendar: c) == .returning(days: 62, landmark: .newMonth))
        // Dienstag, 5.1.2027 → keine Marke
        #expect(Comeback.state(lastActivity: at(2026, 12, 22, in: c), now: at(2027, 1, 5, in: c), calendar: c) == .returning(days: 14, landmark: nil))
    }

    @Test func newYearBeatsMondayAndFirstOfMonth() {
        let c = calendar()   // 1.1.2029 ist ein Montag
        #expect(Comeback.state(lastActivity: at(2028, 12, 1, in: c), now: at(2029, 1, 1, in: c), calendar: c)
                == .returning(days: 31, landmark: .newYear))
    }

    @Test func landmarkFollowsTheLocalDay() {
        // 31.12.2026 23:30 UTC ist in Berlin schon Neujahr, in London noch nicht.
        let utc = calendar("UTC")
        let last = at(2026, 12, 1, in: utc)
        let now = at(2026, 12, 31, hour: 23, minute: 30, in: utc)
        #expect(Comeback.state(lastActivity: last, now: now, calendar: calendar("Europe/Berlin")) == .returning(days: 31, landmark: .newYear))
        #expect(Comeback.state(lastActivity: last, now: now, calendar: calendar("Europe/London")) == .returning(days: 30, landmark: nil))
    }

    // MARK: Texte (Akzeptanz 5)

    @Test func theCardSaysHowLongAndThatItBelongsToWinter() {
        let t = Comeback.texts(state: .returning(days: 12, landmark: nil), jokerWeek: nil, why: nil)
        #expect(t.title == "Schön, dass du wieder da bist")
        #expect(t.lead == "12 Tage Pause. Das gehört zum Winter dazu.")
        #expect(t.streak == "Deine nächste Serie beginnt mit der nächsten Einheit.")
        #expect(t.quote == nil && t.landmark == nil)
        #expect(t.hint == "Die ersten zwei Einheiten dürfen ruhig locker sein.")
    }

    @Test func aCaughtWeekMentionsTheJokerAndSaysTheStreakStands() {
        let c = calendar()
        let t = Comeback.texts(state: .returning(days: 12, landmark: nil), jokerWeek: at(2026, 12, 21, in: c), why: nil, calendar: c)
        #expect(t.streak == "Dein Joker hat die Woche ab 21. Dez. aufgefangen, deine Serie steht.")
    }

    @Test func theRidersOwnSentenceReturnsVerbatim() {
        let t = Comeback.texts(state: .returning(days: 14, landmark: nil), jokerWeek: nil, why: "Im Mai die RTF mit Freunden.")
        #expect(t.quote == "Du hast geschrieben: „Im Mai die RTF mit Freunden.“")
        #expect(t.quoteSpoken == "Zitat: Im Mai die RTF mit Freunden.")
        let blank = Comeback.texts(state: .returning(days: 14, landmark: nil), jokerWeek: nil, why: "   ")
        #expect(blank.quote == nil)
    }

    @Test func landmarksAddTheirSentence() {
        func landmark(_ l: Comeback.Landmark) -> String? {
            Comeback.texts(state: .returning(days: 10, landmark: l), jokerWeek: nil, why: nil).landmark
        }
        #expect(landmark(.newWeek) == "Neue Woche, neuer Anfang.")
        #expect(landmark(.newMonth) == "Neuer Monat, neues Kapitel.")
        #expect(landmark(.newYear) == "Neues Jahr. Dein Frühling kommt trotzdem pünktlich.")
    }

    @Test func oneDayWordsAndTheSingularAreRight() {
        // days ≥ 10, aber der Satz bleibt für jede Zahl korrekt.
        #expect(Comeback.texts(state: .returning(days: 10, landmark: nil), jokerWeek: nil, why: nil).lead.hasPrefix("10 Tage Pause."))
        #expect(Comeback.texts(state: .returning(days: 100, landmark: nil), jokerWeek: nil, why: nil).lead.hasPrefix("100 Tage Pause."))
    }

    @Test func noTextEverJudgesThePause() {
        let c = calendar()
        let whys: [String?] = [nil, "Fit in den Frühling, ohne Stress", "Rad und Studio kombinieren"]
        let jokers: [Date?] = [nil, at(2026, 12, 21, in: c)]
        let landmarks: [Comeback.Landmark?] = [nil, .newWeek, .newMonth, .newYear]
        for days in [10, 11, 25, 60, 200] {
            for why in whys {
                for joker in jokers {
                    for landmark in landmarks {
                        let t = Comeback.texts(state: .returning(days: days, landmark: landmark), jokerWeek: joker, why: why, calendar: c)
                        let all = [t.title, t.lead, t.streak, t.quote ?? "", t.landmark ?? "", t.hint, t.start, t.later, t.accessibility].joined(separator: " ")
                        for word in Self.forbidden { #expect(!all.localizedCaseInsensitiveContains(word), "\(word) in \(all)") }
                        #expect(all.filter { $0 == "!" }.count <= 1)
                        #expect(!all.contains("Fitness") && !all.contains("Form"), "keine Formkurve auf der Karte")
                    }
                }
            }
        }
    }

    @Test func nothingIsShownWhenThereIsNoComeback() {
        let t = Comeback.texts(state: .none, jokerWeek: nil, why: "Egal")
        #expect(t.lead.isEmpty && t.quote == nil)
    }

    @Test func accessibilityReadsTheWholeCardInOrder() {
        let t = Comeback.texts(state: .returning(days: 12, landmark: .newYear), jokerWeek: nil, why: "Im Mai die RTF")
        #expect(t.accessibility.hasPrefix("Schön, dass du wieder da bist. 12 Tage Pause."))
        #expect(t.accessibility.contains("Zitat: Im Mai die RTF"))
        #expect(t.accessibility.contains("Neues Jahr."))
    }

    // MARK: Startaktion (Akzeptanz 4)

    private func workout(_ type: WorkoutType, minutes: Int) -> WorkoutDefinition {
        WorkoutDefinition(title: "Test", type: type, summary: "",
                          segments: [Segment(kind: .steady, duration: minutes * 60, power: 0.7)])
    }

    @Test func easyPlannedWorkoutIsAdjustedToThirtyMinutesAndTenPercentEasier() {
        #expect(Comeback.startAction(planned: workout(.endurance, minutes: 90)) == .adjust(minutes: 30, easierBy: 10))
        #expect(Comeback.startAction(planned: workout(.recovery, minutes: 60)) == .adjust(minutes: 30, easierBy: 10))
    }

    @Test func hardPlannedWorkoutOffersTheSwapToBase() {
        #expect(Comeback.startAction(planned: workout(.threshold, minutes: 60)) == .swapToBase)
        #expect(Comeback.startAction(planned: workout(.vo2max, minutes: 75)) == .swapToBase)
        #expect(Comeback.startAction(planned: workout(.sweetSpot, minutes: 60)) == .swapToBase)
    }

    @Test func tooShortToSwapFallsBackToAdjusting() {
        #expect(Comeback.startAction(planned: workout(.threshold, minutes: 12)) == .adjust(minutes: 30, easierBy: 10))
    }

    @Test func noPlanOpensTheEasyRideFromTheCatalog() {
        #expect(Comeback.startAction(planned: nil) == .easyRide(minutes: 30))
    }

    @Test func easyRideIsThirtyMinutesOfZ2WithWarmupAndCooldown() throws {
        let ride = Comeback.easyRide(minutes: 30)
        #expect(ride.title == "Grundlage 30 min")
        #expect(ride.type == .endurance)
        #expect(ride.totalDuration == 30 * 60)
        #expect(ride.segments.first?.kind == .warmup && ride.segments.last?.kind == .cooldown)
        #expect(ride.estimatedTSS > 10 && ride.estimatedTSS < 30)
        #expect(ride.segments.allSatisfy { ($0.power ?? $0.powerHigh ?? 0) <= WorkoutSwap.basePower + 1e-9 })
    }

    // MARK: Highlight-Slot (Akzeptanz 1, Vorrang)

    private let returning = Comeback.State.returning(days: 12, landmark: nil)

    @Test func comebackWinsTheHighlightSlot() {
        let c = calendar()
        let today = at(2026, 12, 20, in: c)
        #expect(Comeback.highlight(state: returning, today: today, dismissedDay: nil, whyNote: nil, whyPromptDismissed: false,
                                   rodeThisSeason: true, arcActive: true, calendar: c) == .comeback(state: returning))
        // Auch wenn die Warum-Frage noch offen wäre.
        #expect(Comeback.highlight(state: returning, today: today, dismissedDay: nil, whyNote: nil, whyPromptDismissed: false,
                                   rodeThisSeason: true, arcActive: true, calendar: c) != .whyPrompt)
    }

    @Test func laterHidesTheCardForTodayOnly() {
        let c = calendar()
        let today = at(2026, 12, 20, in: c)
        #expect(Comeback.highlight(state: returning, today: today, dismissedDay: Comeback.dayKey(today, calendar: c), whyNote: nil,
                                   whyPromptDismissed: false, rodeThisSeason: true, arcActive: true, calendar: c) == nil)
        let tomorrow = at(2026, 12, 21, in: c)
        #expect(Comeback.highlight(state: .returning(days: 13, landmark: .newWeek), today: tomorrow,
                                   dismissedDay: Comeback.dayKey(today, calendar: c), whyNote: nil, whyPromptDismissed: false,
                                   rodeThisSeason: true, arcActive: true, calendar: c) != nil)
    }

    @Test func noCardOutsideTheWinterArc() {
        let c = calendar()
        #expect(Comeback.highlight(state: returning, today: at(2026, 12, 20, in: c), dismissedDay: nil, whyNote: nil,
                                   whyPromptDismissed: false, rodeThisSeason: true, arcActive: false, calendar: c) == nil)
    }

    @Test func whyPromptAppearsOnceAfterTheFirstRideOfTheSeason() {
        let c = calendar()
        let today = at(2026, 11, 20, in: c)
        func prompt(note: String?, dismissed: Bool, rode: Bool, arc: Bool = true) -> Comeback.Highlight? {
            Comeback.highlight(state: .none, today: today, dismissedDay: nil, whyNote: note, whyPromptDismissed: dismissed,
                               rodeThisSeason: rode, arcActive: arc, calendar: c)
        }
        #expect(prompt(note: nil, dismissed: false, rode: true) == .whyPrompt)
        #expect(prompt(note: nil, dismissed: false, rode: false) == nil)       // erst nach der ersten Fahrt
        #expect(prompt(note: nil, dismissed: true, rode: true) == nil)         // einmalig
        #expect(prompt(note: "Mein Satz", dismissed: false, rode: true) == nil) // schon geschrieben
        #expect(prompt(note: nil, dismissed: false, rode: true, arc: false) == nil)
    }

    @Test func dayKeyIsTheLocalCalendarDay() {
        let utc = calendar("UTC")
        let instant = at(2026, 12, 20, hour: 23, minute: 30, in: utc)
        #expect(Comeback.dayKey(instant, calendar: calendar("Europe/Berlin")) == "2026-12-21")
        #expect(Comeback.dayKey(instant, calendar: calendar("America/New_York")) == "2026-12-20")
    }
}

// MARK: - Store: letzte Aktivität quellenübergreifend

@MainActor
@Suite("Willkommen zurück · letzte Aktivität", .serialized)
struct ComebackStoreTests {
    static var keepAlive: [ModelContainer] = []
    let cal = Calendar.current

    func makeModel() throws -> AppModel {
        let container = try AppEnvironment.makeContainer(inMemory: true)
        Self.keepAlive.append(container)
        AppModel.recoveryWellnessProvider = nil
        return AppModel(context: container.mainContext, secrets: InMemorySecretStore(),
                        defaults: UserDefaults(suiteName: "comeback-\(UUID().uuidString)")!,
                        transport: RoutingTransport { _ in (200, Data("{}".utf8)) })
    }

    private func ride(_ id: Int, daysAgo: Int, now: Date) -> RideSummary {
        RideSummary(id: id, name: "Fahrt", sportType: "VirtualRide", startDate: now.addingTimeInterval(-Double(daysAgo) * 86_400),
                    movingTime: 3600, distance: 30_000, averageWatts: 180, weightedAverageWatts: 190, trainer: true)
    }

    @Test func lastActivityIsTheNewestOfRidesAndStrength() throws {
        let model = try makeModel()
        let now = cal.date(bySettingHour: 12, minute: 0, second: 0, of: cal.startOfDay(for: .now))!
        #expect(model.lastActivityDate(rides: []) == nil)
        let rides = [ride(1, daysAgo: 20, now: now), ride(2, daysAgo: 14, now: now)]
        #expect(model.lastActivityDate(rides: rides) == rides[1].startDate)
        let strengthStart = now.addingTimeInterval(-3 * 86_400)
        _ = model.saveStrengthManual(start: strengthStart, durationMinutes: 45, exertion: 6, legShare: .light, exercises: [])
        #expect(model.lastActivityDate(rides: rides) == strengthStart)
    }

    @Test func otherSportsFromHealthCountAsActivity() throws {
        let model = try makeModel()
        let now = cal.date(bySettingHour: 12, minute: 0, second: 0, of: cal.startOfDay(for: .now))!
        var run = ride(3, daysAgo: 2, now: now)
        run.foreignSport = "running"
        run.healthUUID = UUID().uuidString
        #expect(model.lastActivityDate(rides: [ride(1, daysAgo: 30, now: now), run]) == run.startDate)
    }

    @Test func comebackStateUsesTheOverrideableToday() throws {
        let model = try makeModel()
        let now = cal.date(bySettingHour: 12, minute: 0, second: 0, of: cal.startOfDay(for: .now))!
        let rides = [ride(1, daysAgo: 12, now: now)]
        guard case .returning(let days, _) = model.comebackState(rides: rides, now: now) else {
            Issue.record("12 Tage Pause erwartet")
            return
        }
        #expect(days == 12)
        #expect(model.comebackState(rides: [ride(1, daysAgo: 3, now: now)], now: now) == .none)
        #expect(model.comebackState(rides: [], now: now) == .none)
    }

    @Test func jokerWeekInsideThePauseIsFound() throws {
        let model = try makeModel()
        let now = cal.date(bySettingHour: 12, minute: 0, second: 0, of: cal.startOfDay(for: .now))!
        // Ohne Daten gibt es keine Joker-Woche; die Funktion bleibt ruhig.
        #expect(model.comebackJokerWeek(rides: [], lastActivity: nil, now: now) == nil)
    }

    @Test func easyReturnWorkoutIsPlannedForTodayAndSendable() throws {
        let model = try makeModel()
        let now = cal.date(bySettingHour: 12, minute: 0, second: 0, of: cal.startOfDay(for: .now))!
        let workout = try #require(model.createEasyReturnWorkout(now: now))
        #expect(workout.title == "Grundlage 30 min")
        #expect(workout.status == .planned)
        #expect(workout.definition.totalDuration == 1800)
        #expect(cal.isDate(workout.date, inSameDayAs: now))
        let all = try model.context.fetch(FetchDescriptor<StoredWorkout>())
        #expect(all.count == 1)
        // Zweimal drücken legt keine zweite Einheit an, sondern liefert dieselbe.
        let again = try #require(model.createEasyReturnWorkout(now: now))
        #expect(again.id == workout.id)
        #expect(try model.context.fetch(FetchDescriptor<StoredWorkout>()).count == 1)
    }
}
