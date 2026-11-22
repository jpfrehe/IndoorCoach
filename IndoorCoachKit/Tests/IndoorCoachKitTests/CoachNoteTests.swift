import Foundation
import Testing
@testable import IndoorCoachKit

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Berlin")!
    c.firstWeekday = 2
    return c
}()

private func at(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }

private func context(_ configure: (inout CoachNoteContext) -> Void = { _ in }) -> CoachNoteContext {
    var c = CoachNoteContext(now: at(2026, 12, 18), calendar: cal)
    configure(&c)
    return c
}

private let hardLegs = CheckIn.Answers(legs: .bad, sleep: .ok, mood: .ok)

@Suite("CoachNote")
struct CoachNoteTests {
    // MARK: Regeln einzeln

    @Test func rule1HardCheckInAndRide() {
        let note = CoachNote.make(context { $0.checkIn = hardLegs; $0.shortened = true }, ledger: MomentLedger())
        #expect(note?.rule == "checkin")
        #expect(note?.text == "Trotz schwerer Beine gefahren und klug gekürzt. So bleibt man durch den Winter dran.")
        #expect(note?.source == "aus deinem Check-in")
    }

    @Test func rule1WithoutShorteningSaysOnlyRidden() {
        let note = CoachNote.make(context { $0.checkIn = hardLegs }, ledger: MomentLedger())
        #expect(note?.text == "Trotz schwerer Beine gefahren. So bleibt man durch den Winter dran.")
    }

    @Test func rule1NamesSleepAndMoodToo() {
        let sleep = CoachNote.make(context { $0.checkIn = CheckIn.Answers(legs: .ok, sleep: .bad, mood: .ok) }, ledger: MomentLedger())
        let mood = CoachNote.make(context { $0.checkIn = CheckIn.Answers(legs: .ok, sleep: .ok, mood: .bad) }, ledger: MomentLedger())
        #expect(sleep?.text.hasPrefix("Trotz kurzer Nacht gefahren") == true)
        #expect(mood?.text.hasPrefix("Trotz mieser Laune gefahren") == true)
    }

    @Test func goodCheckInIsNoRule1() {
        let note = CoachNote.make(context { $0.checkIn = CheckIn.Answers(legs: .good, sleep: .good, mood: .good) }, ledger: MomentLedger())
        #expect(note == nil)
    }

    @Test func rule2AerobicEfficiency() {
        let note = CoachNote.make(context { $0.efficiency = .init(watts: 150, fewerBeats: 6, since: at(2026, 11, 3)) }, ledger: MomentLedger())
        #expect(note?.rule == "efficiency")
        #expect(note?.text == "Bei 150 W schlägt dein Herz 6-mal pro Minute weniger als im November.")
        #expect(note?.source == "aus deinen Sekundendaten")
    }

    @Test func rule3WarmupCheckTrend() {
        let note = CoachNote.make(context { $0.warmup = .init(watts: 140, fewerBeats: 4, weeksAgo: 5) }, ledger: MomentLedger())
        #expect(note?.rule == "warmup")
        #expect(note?.text == "Im Aufwärm-Check: 4 Schläge weniger bei gleichen 140 W als vor 5 Wochen.")
        let one = CoachNote.make(context { $0.warmup = .init(watts: 140, fewerBeats: 1, weeksAgo: 1) }, ledger: MomentLedger())
        #expect(one?.text == "Im Aufwärm-Check: 1 Schlag weniger bei gleichen 140 W als vor 1 Woche.")
    }

    @Test func rule4RecordWithComparison() {
        let note = CoachNote.make(context { $0.record = .init(duration: 300, betterBefore: at(2026, 7, 14)) }, ledger: MomentLedger())
        #expect(note?.rule == "record")
        #expect(note?.text == "Deine stärksten 5 Minuten seit Juli.")
        #expect(note?.source == "aus deinen Sekundendaten")
        let none = CoachNote.make(context { $0.record = .init(duration: 60, betterBefore: nil) }, ledger: MomentLedger())
        #expect(none?.text == "Deine stärkste Minute der letzten 90 Tage.")
    }

    @Test func rule5StreakGrew() {
        let note = CoachNote.make(context { $0.streak = .init(weeks: 5, since: at(2026, 11, 9)) }, ledger: MomentLedger())
        #expect(note?.rule == "streak")
        #expect(note?.text == "5 Wochen in Folge dabei, seit dem 9. November.")
        #expect(note?.source == "aus Plan und Fahrten")
        #expect(CoachNote.make(context { $0.streak = .init(weeks: 1, since: at(2026, 12, 7)) }, ledger: MomentLedger()) == nil)
    }

    @Test func rule6FitnessRose() {
        let note = CoachNote.make(context { $0.fitness = .init(from: 24, to: 33, since: at(2026, 11, 1)) }, ledger: MomentLedger())
        #expect(note?.rule == "fitness")
        #expect(note?.text == "Seit dem 1. November ist deine Fitness von 24 auf 33 gestiegen.")
        #expect(note?.source == "geschätzt aus deiner Trainingsbelastung")
        // sinkt oder bleibt gleich: kein Satz
        #expect(CoachNote.make(context { $0.fitness = .init(from: 33, to: 30, since: at(2026, 11, 1)) }, ledger: MomentLedger()) == nil)
    }

    @Test func rule7SeasonSummary() {
        let note = CoachNote.make(context { $0.season = .init(sessions: 12, hours: 9, since: at(2026, 11, 1)) }, ledger: MomentLedger())
        #expect(note?.rule == "season")
        #expect(note?.text == "12 Einheiten seit dem 1. November, 9 Stunden auf der Rolle, während draußen Winter ist.")
        #expect(note?.source == "aus deinen Fahrten")
        let spring = CoachNote.make(CoachNoteContext(now: at(2027, 4, 2), calendar: cal, season: .init(sessions: 1, hours: 1, since: at(2026, 11, 1))),
                                    ledger: MomentLedger())
        #expect(spring == nil) // zu wenig Einheiten für eine Zusammenfassung
        let may = CoachNote.make(CoachNoteContext(now: at(2027, 4, 2), calendar: cal, season: .init(sessions: 30, hours: 1, since: at(2026, 11, 1))),
                                 ledger: MomentLedger())
        #expect(may?.text == "30 Einheiten seit dem 1. November, 1 Stunde auf der Rolle.")
    }

    @Test func comebackWelcomesFirstAndNeverTalksAboutLoss() {
        let note = CoachNote.make(context {
            $0.comebackGapDays = 14
            $0.fitness = .init(from: 40, to: 33, since: at(2026, 11, 1))
            $0.season = .init(sessions: 12, hours: 9, since: at(2026, 11, 1))
        }, ledger: MomentLedger())
        #expect(note?.rule == "comeback")
        #expect(note?.text == "Nach 14 Tagen wieder auf der Rolle. Das Schwerste war der Anfang, und der ist geschafft.")
        #expect(note?.text.localizedCaseInsensitiveContains("gesunken") == false)
        #expect(note?.text.localizedCaseInsensitiveContains("verloren") == false)
    }

    // MARK: Reihenfolge, Abwechslung

    @Test func firstApplicableRuleWins() {
        let note = CoachNote.make(context {
            $0.checkIn = hardLegs
            $0.efficiency = .init(watts: 150, fewerBeats: 6, since: at(2026, 11, 3))
            $0.fitness = .init(from: 24, to: 33, since: at(2026, 11, 1))
        }, ledger: MomentLedger())
        #expect(note?.rule == "checkin")
    }

    @Test func sameRuleDoesNotRepeatWithinThreeNotes() {
        var ledger = MomentLedger()
        let full = context {
            $0.efficiency = .init(watts: 150, fewerBeats: 6, since: at(2026, 11, 3))
            $0.record = .init(duration: 300, betterBefore: at(2026, 7, 14))
            $0.fitness = .init(from: 24, to: 33, since: at(2026, 11, 1))
            $0.season = .init(sessions: 12, hours: 9, since: at(2026, 11, 1))
        }
        var rules: [String] = []
        for _ in 0..<4 {
            guard let note = CoachNote.make(full, ledger: ledger) else { break }
            rules.append(note.rule)
            ledger.recordNoteRule(note.rule)
        }
        // Fenster 3: solange eine Regel unter den letzten drei Notizen steht, ist sie gesperrt – die vierte Notiz weicht auf die nächste aus,
        // erst die fünfte darf wieder die erste Regel nutzen.
        #expect(rules == ["efficiency", "record", "fitness", "season"])
        #expect(CoachNote.make(full, ledger: ledger)?.rule == "efficiency")
    }

    @Test func noApplicableRuleMeansNoNote() {
        #expect(CoachNote.make(context(), ledger: MomentLedger()) == nil)
        var ledger = MomentLedger()
        ledger.recordNoteRule("efficiency")
        let only = context { $0.efficiency = .init(watts: 150, fewerBeats: 6, since: at(2026, 11, 3)) }
        #expect(CoachNote.make(only, ledger: ledger) == nil)
    }

    // MARK: Tonregeln

    private func everyText() -> [CoachNote] {
        var notes: [CoachNote] = []
        let variants: [(inout CoachNoteContext) -> Void] = [
            { $0.checkIn = hardLegs }, { $0.checkIn = hardLegs; $0.shortened = true },
            { $0.checkIn = CheckIn.Answers(legs: .ok, sleep: .bad, mood: .ok) },
            { $0.checkIn = CheckIn.Answers(legs: .ok, sleep: .ok, mood: .bad) },
            { $0.efficiency = .init(watts: 150, fewerBeats: 6, since: at(2026, 11, 3)) },
            { $0.warmup = .init(watts: 140, fewerBeats: 4, weeksAgo: 5) },
            { $0.record = .init(duration: 300, betterBefore: at(2026, 7, 14)) },
            { $0.record = .init(duration: 3600, betterBefore: nil) },
            { $0.streak = .init(weeks: 5, since: at(2026, 11, 9)) },
            { $0.fitness = .init(from: 24, to: 33, since: at(2026, 11, 1)) },
            { $0.season = .init(sessions: 12, hours: 9, since: at(2026, 11, 1)) },
            { $0.comebackGapDays = 11 },
        ]
        for configure in variants { if let note = CoachNote.make(context(configure), ledger: MomentLedger()) { notes.append(note) } }
        return notes
    }

    @Test func everyNoteHasASourceAndFollowsTheToneRules() {
        let notes = everyText()
        #expect(notes.count == 12)
        let banned = ["gesünder", "gesund", "besser als andere", "besser als die anderen", "Diagnose", "gesunken", "Ranking", "Rang ",
                      "schneller als", "Krankheit", "Herzinfarkt", "Risiko"]
        for note in notes {
            #expect(note.text.filter { $0 == "!" }.count <= 1, "\(note.text)")
            #expect(!note.source.isEmpty, "\(note.rule)")
            #expect(note.source.hasPrefix("aus ") || note.source.hasPrefix("geschätzt"), "\(note.source)")
            for word in banned { #expect(!note.text.localizedCaseInsensitiveContains(word), "\(word) in \(note.text)") }
            #expect(note.text.count <= 120, "\(note.text)")
            #expect(!note.text.contains("Sie "), "Du-Form: \(note.text)")
        }
    }

    @Test func noteTextsDoNotUseTheRiderNameAndNotTheServiceNames() {
        for note in everyText() {
            for name in ShareText.serviceNames { #expect(!note.text.localizedCaseInsensitiveContains(name), "\(name) in \(note.text)") }
        }
    }

    @Test func notesVaryAcrossTheRules() {
        #expect(Set(everyText().map(\.rule)).count >= 8)
    }

    // MARK: Aufbau des Kontexts aus Fahrten

    private func ride(_ id: Int, _ date: Date, watts: Double, hr: Double, minutes: Int = 60) -> RideSummary {
        RideSummary(id: id, name: "R\(id)", sportType: "VirtualRide", startDate: date, movingTime: minutes * 60, distance: 30_000,
                    averageWatts: watts, weightedAverageWatts: watts, averageHeartrate: hr, trainer: true)
    }

    @Test func efficiencyComparesSamePowerWithTheFirstThreeWeeksOfTheSeason() {
        let rides = [ride(1, at(2026, 11, 3), watts: 150, hr: 140), ride(2, at(2026, 11, 10), watts: 152, hr: 142),
                     ride(3, at(2026, 12, 10), watts: 160, hr: 150), ride(4, at(2026, 12, 18), watts: 150, hr: 134)]
        let e = CoachNoteContext.efficiency(for: rides[3], in: rides, seasonStart: at(2026, 11, 1), calendar: cal)
        #expect(e?.watts == 150)
        #expect(e?.fewerBeats == 7) // Median der frühen Fahrten 141 → 134
    }

    @Test func efficiencyNeedsThreePercentLessPulse() {
        let rides = [ride(1, at(2026, 11, 3), watts: 150, hr: 140), ride(4, at(2026, 12, 18), watts: 150, hr: 137)]
        #expect(CoachNoteContext.efficiency(for: rides[1], in: rides, seasonStart: at(2026, 11, 1), calendar: cal) == nil)
    }

    @Test func efficiencyIgnoresShortRidesAndOtherPower() {
        let rides = [ride(1, at(2026, 11, 3), watts: 220, hr: 160), ride(2, at(2026, 11, 5), watts: 150, hr: 140, minutes: 10),
                     ride(4, at(2026, 12, 18), watts: 150, hr: 120)]
        #expect(CoachNoteContext.efficiency(for: rides[2], in: rides, seasonStart: at(2026, 11, 1), calendar: cal) == nil)
    }
}
