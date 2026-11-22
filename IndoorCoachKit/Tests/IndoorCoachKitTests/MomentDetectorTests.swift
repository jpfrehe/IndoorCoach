import Foundation
import Testing
@testable import IndoorCoachKit

// MARK: - Helpers (fester Kalender: Europa/Berlin, Wochenstart Montag)

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Berlin")!
    c.firstWeekday = 2
    c.minimumDaysInFirstWeek = 4
    return c
}()

private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

/// „Jetzt“ in allen Tests: Freitag, 18. Dezember 2026, 12:00.
private let now = at(2026, 12, 18)

private func ride(_ id: Int, _ date: Date, curve: [Int: Double]? = nil, minutes: Int = 60, watts: Double = 150,
                  sport: String = "VirtualRide") -> RideSummary {
    var r = RideSummary(id: id, name: "Fahrt \(id)", sportType: sport, startDate: date, movingTime: minutes * 60, distance: 30_000,
                        averageWatts: watts, weightedAverageWatts: watts + 10, trainer: true)
    r.powerCurve = curve
    return r
}

private func trophy(_ id: String, _ kind: Trophy.Kind, title: String = "T", on date: Date?) -> Trophy {
    Trophy(id: id, kind: kind, title: title, condition: "c", detail: nil, symbol: "trophy", earnedOn: date)
}

private func level(_ n: Int, on date: Date?) -> Trophy {
    trophy("level-\(n)", .level, title: "Level \(n) · \(WinterArc.levels[n - 1].name)", on: date)
}

private func input(rides: [RideSummary] = [], trophies: [Trophy] = [], challenges: [Challenges.Challenge] = [],
                   weeks: [MomentInput.WeekPlan] = [], season: String = "2026") -> MomentInput {
    MomentInput(season: season, seasonStart: at(2026, 11, 1, 0), rides: rides, trophies: trophies, challenges: challenges,
                weeks: weeks, calendar: cal)
}

/// Ein bereits ausgewertetes Ledger (kein Erststart).
private func ready(_ seen: [String] = []) -> MomentLedger {
    var l = MomentLedger()
    l.isInitialized = true
    l.markSeen(seen)
    return l
}

private func challenge(_ id: String, title: String, doneOn: Date, by rideID: Int?) -> Challenges.Challenge {
    Challenges.Challenge(id: id, kind: .indoor500, title: title, rule: "500 Indoor-Minuten", symbol: "gift", start: at(2026, 12, 24, 0),
                         end: at(2027, 1, 1, 0), goal: 500, unit: .minutes, progress: 500, state: .completed(on: doneOn),
                         completedByRideID: rideID)
}

@Suite("MomentDetector")
struct MomentDetectorTests {
    // MARK: Level = Etappe

    @Test func freshLevelUpBecomesOneMomentWithStage() {
        let r = ride(1, at(2026, 12, 18, 9))
        let batch = MomentDetector.detect(input(rides: [r], trophies: [level(4, on: at(2026, 12, 18, 0))]), ledger: ready(["first-2026"]), now: now)
        let m = try! #require(batch.headline)
        #expect(m.kind == .levelUp)
        #expect(m.id == "level-4-2026")
        #expect(m.headline == "Level 4 · Rollen-Routine")
        #expect(m.detail == "Etappe 4 von 10: Stilfser Joch, 2757 m")
        #expect(m.rideID == 1)
        #expect(batch.moments.count == 1)
    }

    @Test func levelOlderThan72HoursStaysQuiet() {
        let batch = MomentDetector.detect(input(trophies: [level(4, on: now.addingTimeInterval(-73 * 3600))]), ledger: ready(), now: now)
        #expect(batch.isEmpty)
    }

    @Test func freshnessBoundaryIsInclusiveAt72Hours() {
        let inside = MomentDetector.detect(input(trophies: [level(3, on: now.addingTimeInterval(-72 * 3600))]), ledger: ready(), now: now)
        let outside = MomentDetector.detect(input(trophies: [level(3, on: now.addingTimeInterval(-72 * 3600 - 1))]), ledger: ready(), now: now)
        #expect(inside.headline?.id == "level-3-2026")
        #expect(outside.isEmpty)
    }

    @Test func levelOneIsNeverAPeak() {
        let batch = MomentDetector.detect(input(trophies: [level(1, on: now)]), ledger: ready(), now: now)
        #expect(batch.isEmpty)
    }

    @Test func twoLevelsAtOnceCelebrateTheHighestAndMarkTheOtherSeen() {
        let evaluation = MomentDetector.evaluate(input(trophies: [level(3, on: at(2026, 12, 17, 0)), level(4, on: at(2026, 12, 18, 0))]),
                                                 ledger: ready(), now: now)
        #expect(evaluation.batch.moments.map(\.id) == ["level-4-2026"])
        #expect(evaluation.ledger.hasSeen("level-3-2026"))
        #expect(!evaluation.ledger.hasSeen("level-4-2026"))
    }

    @Test func seasonKeyIsPartOfTheID() {
        let a = MomentDetector.detect(input(trophies: [level(4, on: now)], season: "2026"), ledger: ready(), now: now)
        let b = MomentDetector.detect(input(trophies: [level(4, on: now)], season: "2027"), ledger: ready(), now: now)
        #expect(a.headline?.id == "level-4-2026")
        #expect(b.headline?.id == "level-4-2027")
        #expect(MomentDetector.detect(input(trophies: [level(4, on: now)], season: "2027"), ledger: ready(["level-4-2026"]), now: now).headline != nil)
    }

    // MARK: Deduplizierung, Neustart

    @Test func sameIDNeverAppearsTwice() {
        let i = input(trophies: [level(4, on: now)])
        let first = MomentDetector.evaluate(i, ledger: ready(), now: now)
        let acknowledged = MomentDetector.acknowledged(first.batch, in: first.ledger, noteRule: nil)
        #expect(MomentDetector.detect(i, ledger: acknowledged, now: now).isEmpty)
    }

    @Test func ledgerSurvivesARestart() throws {
        let defaults = try #require(UserDefaults(suiteName: "moments-restart-\(UUID().uuidString)"))
        let i = input(trophies: [level(4, on: now)])
        let first = MomentDetector.evaluate(i, ledger: ready(), now: now)
        MomentDetector.acknowledged(first.batch, in: first.ledger, noteRule: "record").save(to: defaults)
        let reloaded = MomentLedger.load(from: defaults)
        #expect(MomentDetector.detect(i, ledger: reloaded, now: now).isEmpty)
        #expect(reloaded.recentNoteRules == ["record"])
    }

    @Test func unacknowledgedMomentComesBackAfterARestart() {
        let i = input(trophies: [level(4, on: now)])
        let first = MomentDetector.evaluate(i, ledger: ready(), now: now)
        #expect(MomentDetector.detect(i, ledger: first.ledger, now: now).headline?.id == "level-4-2026")
    }

    // MARK: Bestleistung

    private func recordFixture() -> (rides: [RideSummary], newest: RideSummary) {
        let old = ride(10, at(2026, 12, 3, 18), curve: [300: 261, 1200: 230])
        var newest = ride(11, at(2026, 12, 18, 9), curve: [300: 268, 1200: 240])
        newest.name = "Sweet Spot 3×12"
        return ([old, newest], newest)
    }

    @Test func recordCollapsesToTheLongestDurationAndMarksTheRestSeen() {
        let (rides, _) = recordFixture()
        let evaluation = MomentDetector.evaluate(input(rides: rides), ledger: ready(), now: now)
        let m = try! #require(evaluation.batch.moments.first { $0.kind == .record })
        #expect(m.id == "record-1200-11")
        #expect(m.headline == "Neue Bestleistung: 20 min · 240 W")
        #expect(m.rideID == 11)
        #expect(evaluation.ledger.hasSeen("record-300-11"))
    }

    @Test func recordDetailNamesTheGainAndTheDateOfThePreviousBest() {
        let (rides, _) = recordFixture()
        let m = try! #require(MomentDetector.detect(input(rides: rides), ledger: ready(), now: now).moments.first { $0.kind == .record })
        #expect(m.detail == "+10 W gegenüber deiner bisherigen Bestleistung (3. Dez.)")
    }

    @Test func recordNeedsAnotherRideInTheWindow() {
        let only = ride(11, at(2026, 12, 18, 9), curve: [300: 268])
        let batch = MomentDetector.detect(input(rides: [only]), ledger: ready(["first-2026", "seconds-first"]), now: now)
        #expect(batch.moments.filter { $0.kind == .record }.isEmpty)
    }

    @Test func rideWithoutSecondsDataIsNoRecord() {
        let rides = [ride(10, at(2026, 12, 3), watts: 120), ride(11, at(2026, 12, 18, 9), watts: 300)]
        let batch = MomentDetector.detect(input(rides: rides), ledger: ready(["first-2026"]), now: now)
        #expect(batch.moments.filter { $0.kind == .record }.isEmpty)
    }

    @Test func oldRecordRideIsNotCelebrated() {
        let rides = [ride(10, at(2026, 11, 3), curve: [300: 250]), ride(11, at(2026, 12, 10, 9), curve: [300: 268])]
        #expect(MomentDetector.detect(input(rides: rides), ledger: ready(["first-2026"]), now: now).moments.filter { $0.kind == .record }.isEmpty)
    }

    // MARK: eFTP-Sprung

    private func ftpRides(newBest: Double) -> [RideSummary] {
        [ride(20, at(2026, 11, 20, 18), curve: [1200: 243]), // eFTP 231
         ride(21, at(2026, 12, 18, 9), curve: [1200: newBest])]
    }

    @Test func ftpRiseFromTheCelebratedBaselineBecomesAMoment() {
        var ledger = ready(["first-2026", "seconds-first"])
        ledger.lastCelebratedFTP = 231
        let evaluation = MomentDetector.evaluate(input(rides: ftpRides(newBest: 251)), ledger: ledger, now: now)
        let m = try! #require(evaluation.batch.moments.first { $0.kind == .ftpRise })
        #expect(m.id == "ftp-238-2026")
        #expect(m.headline == "Deine Schwelle ist gestiegen: 231 → 238 W")
        // Erst die Bestätigung merkt sich den gefeierten Wert.
        #expect(evaluation.ledger.lastCelebratedFTP == 231)
        let done = MomentDetector.acknowledged(evaluation.batch, in: evaluation.ledger, noteRule: nil)
        #expect(done.lastCelebratedFTP == 238)
    }

    @Test func ftpRiseBelowTwoPercentIsQuiet() {
        var ledger = ready(["first-2026", "seconds-first", "record-1200-21"])
        ledger.lastCelebratedFTP = 231
        let batch = MomentDetector.detect(input(rides: ftpRides(newBest: 246)), ledger: ledger, now: now) // eFTP 233,7 = +1,2 %
        #expect(batch.moments.filter { $0.kind == .ftpRise }.isEmpty)
    }

    @Test func ftpWithoutBaselineSetsOneAndStaysQuiet() {
        let first = [ride(21, at(2026, 12, 18, 9), curve: [1200: 251])]
        let evaluation = MomentDetector.evaluate(input(rides: first), ledger: ready(["first-2026", "seconds-first"]), now: now)
        #expect(evaluation.batch.moments.filter { $0.kind == .ftpRise }.isEmpty)
        #expect(evaluation.ledger.lastCelebratedFTP == 238)
    }

    @Test func staleFtpRiseOnlyRaisesTheBaseline() {
        let rides = [ride(20, at(2026, 11, 20, 18), curve: [1200: 243]), ride(21, at(2026, 12, 8, 9), curve: [1200: 260])]
        var ledger = ready(["first-2026", "seconds-first"])
        ledger.lastCelebratedFTP = 231
        let evaluation = MomentDetector.evaluate(input(rides: rides), ledger: ledger, now: now)
        #expect(evaluation.batch.moments.filter { $0.kind == .ftpRise }.isEmpty)
        #expect(evaluation.ledger.lastCelebratedFTP == 247)
    }

    // MARK: Challenge, Serie, Kraft, Sekundendaten

    @Test func completedChallengeIsCelebratedOnce() {
        let c = challenge("indoor500-2026", title: "Indoor-500", doneOn: at(2026, 12, 18, 8), by: 5)
        let m = try! #require(MomentDetector.detect(input(challenges: [c]), ledger: ready(), now: now).headline)
        #expect(m.kind == .challengeCompleted)
        #expect(m.id == "challenge-indoor500-2026")
        #expect(m.headline == "Indoor-500 geschafft")
        #expect(m.rideID == 5)
    }

    @Test func streakMilestonesKeepOnlyTheHighest() {
        let evaluation = MomentDetector.evaluate(
            input(trophies: [trophy("streak-4", .streak, on: at(2026, 12, 17)), trophy("streak-8", .streak, on: at(2026, 12, 17))]),
            ledger: ready(), now: now)
        #expect(evaluation.batch.moments.map(\.id) == ["streak-8-2026"])
        #expect(evaluation.batch.headline?.headline == "8 Wochen in Folge")
        #expect(evaluation.ledger.hasSeen("streak-4-2026"))
    }

    @Test func strengthTier() {
        let m = try! #require(MomentDetector.detect(input(trophies: [trophy("strengthWinter-16", .strength, on: at(2026, 12, 17))]),
                                                    ledger: ready(), now: now).headline)
        #expect(m.kind == .strengthTier)
        #expect(m.id == "strength-16-2026")
        #expect(m.headline == "Kraft-Winter · 16")
    }

    @Test func firstRideWithSecondsDataIsSekundengenau() {
        let r = ride(30, at(2026, 12, 17, 18), curve: [300: 200])
        let t = trophy("second-data", .secondData, on: r.startDate)
        let m = try! #require(MomentDetector.detect(input(rides: [r], trophies: [t]), ledger: ready(["first-2026"]), now: now).headline)
        #expect(m.kind == .secondData)
        #expect(m.id == "seconds-first")
        #expect(m.headline == "Sekundengenau")
        #expect(m.rideID == 30)
    }

    // MARK: Comeback, erste Fahrt, Woche

    @Test func comebackAfterTenDays() {
        let rides = [ride(40, at(2026, 11, 30, 18)), ride(41, at(2026, 12, 18, 9))]
        let batch = MomentDetector.detect(input(rides: rides), ledger: ready(["first-2026"]), now: now)
        let m = try! #require(batch.headline)
        #expect(m.kind == .comeback)
        #expect(m.id == "comeback-41")
        #expect(m.headline == "Du bist zurück")
        #expect(m.detail == "Nach 18 Tagen Pause wieder im Sattel.")
    }

    @Test func nineDaysAreNoComeback() {
        let rides = [ride(40, at(2026, 12, 9, 18)), ride(41, at(2026, 12, 18, 9))]
        #expect(MomentDetector.detect(input(rides: rides), ledger: ready(["first-2026"]), now: now).isEmpty)
    }

    @Test func comebackNeedsAPreviousRide() {
        let batch = MomentDetector.detect(input(rides: [ride(41, at(2026, 12, 18, 9))]), ledger: ready(["first-2026"]), now: now)
        #expect(batch.moments.filter { $0.kind == .comeback }.isEmpty)
    }

    @Test func firstRideOfTheSeasonIsStartInGarmisch() {
        let batch = MomentDetector.detect(input(rides: [ride(50, at(2026, 12, 17, 18))]), ledger: ready(), now: now)
        let m = try! #require(batch.headline)
        #expect(m.kind == .firstRide)
        #expect(m.id == "first-2026")
        #expect(m.headline == "Start in Garmisch")
        // eine zweite Fahrt ist keine erste
        let two = [ride(50, at(2026, 11, 20, 18)), ride(51, at(2026, 12, 17, 18))]
        #expect(MomentDetector.detect(input(rides: two), ledger: ready(), now: now).moments.filter { $0.kind == .firstRide }.isEmpty)
    }

    @Test func ridesBeforeTheSeasonDoNotCountAsFirstRide() {
        let rides = [ride(50, at(2026, 10, 20, 18)), ride(51, at(2026, 12, 17, 18))]
        let batch = MomentDetector.detect(input(rides: rides), ledger: ready(), now: now)
        #expect(batch.moments.contains { $0.kind == .firstRide && $0.rideID == 51 })
    }

    @Test func weekPlanDoneNeedsAtLeastTwoUnitsAllDone() {
        let monday = at(2026, 12, 14, 0)
        let rides = [ride(60, at(2026, 12, 15, 18)), ride(61, at(2026, 12, 17, 18))]
        func moment(planned: Int, done: Int) -> Moment? {
            MomentDetector.detect(input(rides: rides, weeks: [.init(start: monday, planned: planned, done: done)]),
                                  ledger: ready(["first-2026"]), now: now).headline
        }
        let m = try! #require(moment(planned: 4, done: 4))
        #expect(m.kind == .weekPlanDone)
        #expect(m.id == "week-2026-12-14")
        #expect(m.headline == "Plan der Woche geschafft · 4/4")
        #expect(m.rideID == 61)
        #expect(moment(planned: 4, done: 3) == nil)
        #expect(moment(planned: 1, done: 1) == nil)
    }

    @Test func weekKeyUsesTheCalendarTimeZoneNotUTC() {
        // Montag 00:00 in Berlin ist Sonntag 23:00 UTC: der Schlüssel muss der Berliner Montag sein.
        let monday = at(2026, 12, 14, 0)
        let rides = [ride(60, at(2026, 12, 14, 0, 30)), ride(61, at(2026, 12, 17, 18))]
        let m = MomentDetector.detect(input(rides: rides, weeks: [.init(start: monday, planned: 2, done: 2)]),
                                      ledger: ready(["first-2026"]), now: now).headline
        #expect(m?.id == "week-2026-12-14")
    }

    // MARK: Priorität, Obergrenze

    @Test func batchKeepsThreeByPriorityAndMarksTheRestSeen() {
        let rides = [ride(40, at(2026, 11, 30, 18), curve: [300: 200]), ride(41, at(2026, 12, 18, 9), curve: [300: 240])]
        let trophies = [level(4, on: at(2026, 12, 18, 0)), trophy("streak-4", .streak, on: at(2026, 12, 17)),
                        trophy("second-data", .secondData, on: rides[0].startDate)]
        let weeks = [MomentInput.WeekPlan(start: at(2026, 12, 14, 0), planned: 2, done: 2)]
        let evaluation = MomentDetector.evaluate(input(rides: rides, trophies: trophies, weeks: weeks), ledger: ready(), now: now)
        // levelUp 10, record 9, comeback 6 | Rest: streak 5, week 3 (second-data ist 18 Tage alt)
        #expect(evaluation.batch.moments.map(\.kind) == [.levelUp, .record, .comeback])
        #expect(evaluation.ledger.hasSeen("streak-4-2026"))
        #expect(evaluation.ledger.hasSeen("week-2026-12-14"))
        #expect(!evaluation.ledger.hasSeen("level-4-2026"))
    }

    // MARK: Erstauswertung

    private func yearlyHistory() -> MomentInput {
        // 210 Tage Import: viele Fahrten, alle Trophäen bereits verdient, nur die jüngste Fahrt ist frisch.
        let rides = (0..<70).map { ride(100 + $0, now.addingTimeInterval(-Double($0) * 3 * 86_400 - 6 * 3600), curve: [300: 200 + Double(70 - $0)]) }
        let trophies = [level(2, on: at(2026, 11, 8, 0)), level(3, on: at(2026, 11, 20, 0)), level(4, on: at(2026, 12, 17, 0)),
                        trophy("streak-4", .streak, on: at(2026, 12, 6)), trophy("second-data", .secondData, on: at(2026, 5, 20))]
        return input(rides: rides, trophies: trophies)
    }

    @Test func firstEvaluationOf210DaysCelebratesAtMostOneMoment() {
        let evaluation = MomentDetector.evaluate(yearlyHistory(), ledger: MomentLedger(), now: now)
        #expect(evaluation.batch.moments.count == 1)
        #expect(evaluation.batch.headline?.kind == .levelUp)
        #expect(evaluation.ledger.isInitialized)
        // alles Verdiente ist still gesehen, nur der gefeierte Moment nicht
        for id in ["level-2-2026", "level-3-2026", "streak-4-2026", "seconds-first", "first-2026"] { #expect(evaluation.ledger.hasSeen(id), "\(id)") }
        #expect(!evaluation.ledger.hasSeen("level-4-2026"))
    }

    @Test func secondEvaluationAfterTheFirstShowsNothing() {
        let i = yearlyHistory()
        let first = MomentDetector.evaluate(i, ledger: MomentLedger(), now: now)
        let acknowledged = MomentDetector.acknowledged(first.batch, in: first.ledger, noteRule: nil)
        #expect(MomentDetector.detect(i, ledger: acknowledged, now: now.addingTimeInterval(3600)).isEmpty)
    }

    @Test func firstEvaluationWithoutRidesStaysUninitialised() {
        let evaluation = MomentDetector.evaluate(input(), ledger: MomentLedger(), now: now)
        #expect(evaluation.batch.isEmpty)
        #expect(!evaluation.ledger.isInitialized)
    }

    // MARK: Später ansehen

    @Test func replayFindsTheMomentsOfOneRideRegardlessOfAgeAndLedger() {
        let old = at(2026, 11, 15, 18)
        let rides = [ride(70, old, curve: [300: 210]), ride(71, at(2026, 11, 20, 18), curve: [300: 230])]
        let i = input(rides: rides, trophies: [level(2, on: at(2026, 11, 20, 0))])
        let ledger = ready(["level-2-2026", "record-300-71"])
        let moments = MomentDetector.moments(forRide: 71, input: i, now: now)
        #expect(Set(moments.map(\.kind)) == [.levelUp, .record])
        #expect(MomentDetector.detect(i, ledger: ledger, now: now).isEmpty)
        #expect(MomentDetector.moments(forRide: 70, input: i, now: now).filter { $0.kind == .levelUp }.isEmpty)
    }
}
