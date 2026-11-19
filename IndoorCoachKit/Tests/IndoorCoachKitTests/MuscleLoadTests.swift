import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("MuscleLoad")
struct MuscleLoadTests {
    /// Fixer Zeitpunkt, zeitzonenunabhängig (UTC-Sekunden).
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func hours(_ h: Double) -> TimeInterval { h * 3600 }

    /// Einheit, die `endedHoursAgo` Stunden vor `now` endet.
    private func session(endedHoursAgo: Double, minutes: Int = 60, exertion: Int? = 6,
                         legs: LegInvolvement? = nil) -> StrengthSession {
        let end = now.addingTimeInterval(-hours(endedHoursAgo))
        return StrengthSession(start: end.addingTimeInterval(-Double(minutes) * 60), durationSeconds: minutes * 60,
                               exertion: exertion, legShare: legs)
    }

    @Test func loadIsExertionTimesMinutes() {
        let s = session(endedHoursAgo: 1, minutes: 45, exertion: 7)
        #expect(MuscleLoad.load(of: s) == 315)
        #expect(MuscleLoad.status(of: s) == .value(315))
    }

    @Test func missingExertionIsNotComputed() {
        let s = session(endedHoursAgo: 1, exertion: nil)
        #expect(MuscleLoad.load(of: s) == nil)
        #expect(MuscleLoad.status(of: s) == .missing)
    }

    @Test func zeroExertionIsZeroLoadNotMissing() {
        #expect(MuscleLoad.status(of: session(endedHoursAgo: 1, exertion: 0)) == .value(0))
    }

    @Test func outOfRangeExertionOrZeroDurationIsMissing() {
        #expect(MuscleLoad.status(of: session(endedHoursAgo: 1, exertion: 11)) == .missing)
        #expect(MuscleLoad.status(of: session(endedHoursAgo: 1, minutes: 0, exertion: 5)) == .missing)
    }

    @Test func windowIncludesExactly72HoursAndExcludesOlder() {
        let inside = session(endedHoursAgo: 72, minutes: 60, exertion: 5)      // 300, Grenze zählt noch
        let outside = session(endedHoursAgo: 72.01, minutes: 60, exertion: 5)
        let sum = MuscleLoad.sum(of: [inside, outside], endingAt: now)
        #expect(sum.total == 300)
        #expect(sum.counted == 1)
    }

    @Test func windowExcludesFutureSessions() {
        let future = session(endedHoursAgo: -1)
        #expect(MuscleLoad.sum(of: [future], endingAt: now).counted == 0)
    }

    @Test func sumCountsMissingSeparately() {
        let a = session(endedHoursAgo: 5, minutes: 30, exertion: 8)   // 240
        let b = session(endedHoursAgo: 30, exertion: nil)
        let sum = MuscleLoad.sum(of: [a, b], endingAt: now)
        #expect(sum.total == 240)
        #expect(sum.counted == 1)
        #expect(sum.missing == 1)
    }

    @Test func customWindowHours() {
        let s = session(endedHoursAgo: 30, minutes: 60, exertion: 5)
        #expect(MuscleLoad.sum(of: [s], withinHours: 24, endingAt: now).total == 0)
        #expect(MuscleLoad.sum(of: [s], withinHours: 48, endingAt: now).total == 300)
    }

    @Test func weeklySumUsesCalendarWeekInGivenTimeZone() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        cal.firstWeekday = 2
        func at(_ d: Int, _ h: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h))! }
        // Mo 2.11.2026 bis So 8.11.; Mo 9.11. gehört zur nächsten Woche
        let sunLate = StrengthSession(start: at(8, 22), durationSeconds: 3600, exertion: 5)
        let monEarly = StrengthSession(start: at(9, 0), durationSeconds: 3600, exertion: 5)
        let monStart = StrengthSession(start: at(2, 0), durationSeconds: 3600, exertion: 4)
        let prevSun = StrengthSession(start: at(1, 23), durationSeconds: 3600, exertion: 9)
        let week = MuscleLoad.weeklySum(of: [sunLate, monEarly, monStart, prevSun], weekContaining: at(4, 12), calendar: cal)
        #expect(week.total == 300 + 240)
        #expect(week.counted == 2)
    }

    // MARK: Schwere Beine

    @Test func heavyLegsWithinWindow() {
        let heavy = session(endedHoursAgo: 20, legs: .heavy)
        #expect(MuscleLoad.heavyLegsWithin(hours: 24, of: [heavy], now: now))
        #expect(!MuscleLoad.heavyLegsWithin(hours: 12, of: [heavy], now: now))
        #expect(!MuscleLoad.heavyLegsWithin(hours: 72, of: [session(endedHoursAgo: 5, legs: .light)], now: now))
    }

    @Test func heavyLegsDerivedFromExercises() {
        let end = now.addingTimeInterval(-hours(2))
        let s = StrengthSession(start: end.addingTimeInterval(-3600), durationSeconds: 3600,
                                exercises: [PerformedExercise(exerciseID: "leg_press")])
        #expect(MuscleLoad.heavyLegsWithin(hours: 72, of: [s], now: now))
    }

    @Test func heavyLegsWorkWithoutExertion() {
        // Fehlende Härte darf die Beine-Regel nicht aushebeln.
        #expect(MuscleLoad.heavyLegsWithin(hours: 24, of: [session(endedHoursAgo: 3, exertion: nil, legs: .heavy)], now: now))
    }

    // MARK: Schlüsseleinheit

    @Test func conflictWhenHeavyLegsLessThan24hBefore() throws {
        let heavy = session(endedHoursAgo: 0, legs: .heavy)
        let planned = now.addingTimeInterval(hours(23.9))
        let c = try #require(MuscleLoad.keySessionConflict(sessions: [heavy], plannedKeySessionAt: planned))
        #expect(c.hoursBetween < 24)
        #expect(c.sessionID == heavy.id)
        #expect(c.intensity == .vo2)
    }

    @Test func noConflictExactly24h() {
        let heavy = session(endedHoursAgo: 0, legs: .heavy)
        #expect(MuscleLoad.keySessionConflict(sessions: [heavy], plannedKeySessionAt: now.addingTimeInterval(hours(24))) == nil)
    }

    @Test func conflictAtOneSecondBefore24h() {
        let heavy = session(endedHoursAgo: 0, legs: .heavy)
        #expect(MuscleLoad.keySessionConflict(sessions: [heavy], plannedKeySessionAt: now.addingTimeInterval(hours(24) - 1)) != nil)
    }

    @Test func noConflictForLightLegsOrAfterPlanned() {
        let planned = now.addingTimeInterval(hours(10))
        #expect(MuscleLoad.keySessionConflict(sessions: [session(endedHoursAgo: 0, legs: .light)], plannedKeySessionAt: planned) == nil)
        let later = StrengthSession(start: planned.addingTimeInterval(hours(1)), durationSeconds: 3600, legShare: .heavy)
        #expect(MuscleLoad.keySessionConflict(sessions: [later], plannedKeySessionAt: planned) == nil)
    }

    @Test func conflictPicksMostRecentHeavySessionAndKeepsIntensity() throws {
        let older = session(endedHoursAgo: 10, legs: .heavy)
        let newer = session(endedHoursAgo: 2, legs: .heavy)
        let planned = now.addingTimeInterval(hours(6))
        let c = try #require(MuscleLoad.keySessionConflict(sessions: [older, newer], plannedKeySessionAt: planned, intensity: .threshold))
        #expect(c.sessionID == newer.id)
        #expect(c.intensity == .threshold)
        #expect(abs(c.hoursBetween - 8) < 0.001)
    }

    @Test func conflictReasonMentionsFaustregel() throws {
        let c = try #require(MuscleLoad.keySessionConflict(sessions: [session(endedHoursAgo: 0, legs: .heavy)],
                                                          plannedKeySessionAt: now.addingTimeInterval(hours(12))))
        #expect(c.reasonText.contains("Faustregel"))
        #expect(c.reasonKey == "muscle.conflict.heavyLegsBeforeKeySession")
    }

    // MARK: Gleicher Tag

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }
    private func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!
    }

    @Test func sameDayHintWhenStrengthBeforeIntervalsWithinThreeHours() {
        let strength = StrengthSession(start: at(10, 8), durationSeconds: 3600)             // Ende 09:00
        #expect(MuscleLoad.sameDayOrder(strength: strength, intervalsAt: at(10, 11, 59), calendar: cal) == .intervalsFirst)
    }

    @Test func noSameDayHintAtExactlyThreeHours() {
        let strength = StrengthSession(start: at(10, 8), durationSeconds: 3600)
        #expect(MuscleLoad.sameDayOrder(strength: strength, intervalsAt: at(10, 12), calendar: cal) == nil)
    }

    @Test func noSameDayHintWhenStrengthAfterIntervalsOrOtherDay() {
        let strength = StrengthSession(start: at(10, 18), durationSeconds: 3600)
        #expect(MuscleLoad.sameDayOrder(strength: strength, intervalsAt: at(10, 17), calendar: cal) == nil)
        #expect(MuscleLoad.sameDayOrder(strength: strength, intervalsAt: at(11, 19), calendar: cal) == nil)
    }

    @Test func sameDayHintWhenOverlapping() {
        let strength = StrengthSession(start: at(10, 9), durationSeconds: 3600)
        #expect(MuscleLoad.sameDayOrder(strength: strength, intervalsAt: at(10, 9, 30), calendar: cal) == .intervalsFirst)
    }

    @Test func sameDayRespectsTimeZoneOfCalendar() {
        // 23:30 Berlin und 00:30 Berlin am Folgetag: verschiedene Tage, obwohl nur 1 h Abstand.
        let strength = StrengthSession(start: at(10, 22, 30), durationSeconds: 3600)         // Ende 23:30
        #expect(MuscleLoad.sameDayOrder(strength: strength, intervalsAt: at(11, 0, 30), calendar: cal) == nil)
    }

    @Test func sameDayHintReasonMentionsFaustregel() {
        #expect(MuscleLoad.SameDayHint.intervalsFirst.reasonText.contains("Faustregel"))
    }

    @Test func keyIntensitiesAreAllSensitiveToHeavyLegs() {
        for i in MuscleLoad.KeyIntensity.allCases { #expect(i.avoidAfterHeavyLegs) }
    }
}
