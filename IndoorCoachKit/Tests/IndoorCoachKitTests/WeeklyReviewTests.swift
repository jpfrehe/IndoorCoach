import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("Wochenrückblick")
struct WeeklyReviewTests {
    // MARK: Helpers

    static func calendar(_ zone: String = "Europe/Berlin") -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }

    static func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0, _ sec: Int = 0,
                   calendar: Calendar = calendar()) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: sec))!
    }

    /// Monday 16 Nov 2026 – Sunday 22 Nov 2026 (ISO week 47).
    static let monday = at(2026, 11, 16, 0)
    static let ftp = 250
    static let hr = RelativeEffort.HeartRateProfile(resting: 50, max: 190)

    static func ride(_ id: Int, day: Int, minutes: Int = 60, watts: Double = 200, effort: Double? = nil,
                     curve: [Int: Double]? = nil) -> RideSummary {
        var r = RideSummary(id: id, name: "Ride \(id)", sportType: "VirtualRide", startDate: at(2026, 11, day, 18),
                            movingTime: minutes * 60, distance: 30_000, averageWatts: watts, weightedAverageWatts: watts,
                            trainer: true)
        r.stravaRelativeEffort = effort
        r.powerCurve = curve
        return r
    }

    static func rideOn(_ id: Int, _ date: Date, effort: Double) -> RideSummary {
        var r = RideSummary(id: id, name: "R\(id)", sportType: "VirtualRide", startDate: date, movingTime: 3600,
                            distance: 1, averageWatts: 200, trainer: true)
        r.stravaRelativeEffort = effort
        return r
    }

    static func planned(_ day: Int, tss: Double = 60, done: Bool) -> WeeklyReview.PlannedItem {
        .init(date: at(2026, 11, day, 18), tss: tss, done: done)
    }

    static func point(_ day: Date, fitness: Double, form: Double = 0) -> FitnessFreshness.Point {
        .init(date: day, load: 0, fitness: fitness, fatigue: fitness - form, form: form)
    }

    static func build(rides: [RideSummary] = [], planned: [WeeklyReview.PlannedItem] = [],
                      points: [FitnessFreshness.Point] = [], now: Date = at(2026, 11, 23, 9),
                      calendar: Calendar = calendar()) -> WeeklyReview {
        WeeklyReview.build(weekStart: monday, rides: rides, planned: planned,
                           series: FitnessFreshness.Series(points: points, effortFactor: nil),
                           ftp: ftp, thresholdHeartRate: nil, heartRate: hr, now: now, calendar: calendar)
    }

    // MARK: Visibility window

    @Test func windowOpensSundayAtSixteen() {
        let cal = Self.calendar()
        #expect(WeeklyReview.visibleWeekStart(now: Self.at(2026, 11, 22, 15, 59, 59), calendar: cal) == nil)
        #expect(WeeklyReview.visibleWeekStart(now: Self.at(2026, 11, 22, 16, 0), calendar: cal) == Self.monday)
        #expect(WeeklyReview.visibleWeekStart(now: Self.at(2026, 11, 22, 23, 59, 59), calendar: cal) == Self.monday)
    }

    @Test func windowCoversMondayAndTuesdayForTheLastWeek() {
        let cal = Self.calendar()
        #expect(WeeklyReview.visibleWeekStart(now: Self.at(2026, 11, 23, 0, 0), calendar: cal) == Self.monday)
        #expect(WeeklyReview.visibleWeekStart(now: Self.at(2026, 11, 24, 23, 59, 59), calendar: cal) == Self.monday)
    }

    @Test func windowClosesWednesdayMidnight() {
        let cal = Self.calendar()
        #expect(WeeklyReview.visibleWeekStart(now: Self.at(2026, 11, 25, 0, 0), calendar: cal) == nil)
        #expect(WeeklyReview.visibleWeekStart(now: Self.at(2026, 11, 18, 12), calendar: cal) == nil)
        #expect(WeeklyReview.visibleWeekStart(now: Self.at(2026, 11, 22, 10), calendar: cal) == nil)
    }

    @Test func windowIsTimeZoneSafe() {
        // 15:30 UTC on Sunday is 16:30 in Berlin (UTC+1) but still before 16:00 in UTC.
        let utc = Self.calendar("UTC")
        let instant = Self.at(2026, 11, 22, 15, 30, calendar: utc)
        #expect(WeeklyReview.visibleWeekStart(now: instant, calendar: Self.calendar("Europe/Berlin")) == Self.monday)
        #expect(WeeklyReview.visibleWeekStart(now: instant, calendar: utc) == nil)
        // The week start is local midnight of the Monday in the calendar's own zone.
        let utcMonday = Self.at(2026, 11, 16, 0, calendar: utc)
        #expect(WeeklyReview.visibleWeekStart(now: Self.at(2026, 11, 23, 8, calendar: utc), calendar: utc) == utcMonday)
    }

    @Test func windowIgnoresTheCallersFirstWeekday() {
        var sundayFirst = Self.calendar()
        sundayFirst.firstWeekday = 1
        #expect(WeeklyReview.visibleWeekStart(now: Self.at(2026, 11, 22, 17), calendar: sundayFirst) == Self.monday)
        #expect(WeeklyReview.visibleWeekStart(now: Self.at(2026, 11, 23, 17), calendar: sundayFirst) == Self.monday)
    }

    @Test func weekAcrossDaylightSavingChange() {
        // Last Sunday of October 2026 (the 25th) has 25 hours in Berlin.
        let cal = Self.calendar()
        let monday = Self.at(2026, 10, 19, 0)
        #expect(WeeklyReview.visibleWeekStart(now: Self.at(2026, 10, 25, 16, 30), calendar: cal) == monday)
        #expect(WeeklyReview.visibleWeekStart(now: Self.at(2026, 10, 27, 23, 59), calendar: cal) == monday)
        #expect(WeeklyReview.visibleWeekStart(now: Self.at(2026, 10, 28, 0, 0), calendar: cal) == nil)
    }

    // MARK: Numbers

    @Test func countsRidesHoursAndTSSOfTheWeekOnly() {
        let rides = [Self.ride(1, day: 16), Self.ride(2, day: 18, minutes: 90), Self.ride(3, day: 22),
                     Self.ride(4, day: 15), Self.ride(5, day: 23)]
        let review = Self.build(rides: rides)
        #expect(review.rideCount == 3)
        #expect(abs(review.hours - 3.5) < 0.001)
        // 200 W at FTP 250 → IF 0.8 → 64 TSS per hour.
        #expect(abs(review.actualTSS - 3.5 * 64) < 0.5)
    }

    @Test func sundayNightRideBelongsToTheWeekInLocalTime() {
        let cal = Self.calendar()
        let late = RideSummary(id: 9, name: "Spät", sportType: "VirtualRide", startDate: Self.at(2026, 11, 22, 23, 30, calendar: cal),
                               movingTime: 1800, distance: 10_000, averageWatts: 180, trainer: true)
        let early = RideSummary(id: 10, name: "Früh", sportType: "VirtualRide", startDate: Self.at(2026, 11, 23, 0, 10, calendar: cal),
                                movingTime: 1800, distance: 10_000, averageWatts: 180, trainer: true)
        #expect(Self.build(rides: [late, early], calendar: cal).rideCount == 1)
    }

    @Test func planAdherenceCountsDoneAgainstPlanned() {
        let review = Self.build(rides: [Self.ride(1, day: 16)],
                                planned: [Self.planned(16, tss: 60, done: true), Self.planned(18, tss: 80, done: false),
                                          Self.planned(20, tss: 40, done: false), Self.planned(30, done: false)])
        #expect(review.plannedCount == 3)
        #expect(review.doneCount == 1)
        #expect(review.plannedTSS == 180)
        #expect(abs((review.adherence ?? 0) - 1.0 / 3.0) < 0.001)
    }

    @Test func noPlanMeansNoAdherence() {
        let review = Self.build(rides: [Self.ride(1, day: 16)])
        #expect(review.plannedCount == 0)
        #expect(review.adherence == nil)
    }

    @Test func fitnessChangeRunsFromBeforeTheWeekToItsEnd() {
        let points = [
            Self.point(Self.at(2026, 11, 14, 0), fitness: 40),
            Self.point(Self.at(2026, 11, 15, 0), fitness: 41),   // Sunday before: start value
            Self.point(Self.at(2026, 11, 18, 0), fitness: 42),
            Self.point(Self.at(2026, 11, 22, 0), fitness: 43.1, form: 6),
        ]
        let review = Self.build(points: points)
        #expect(abs((review.fitnessChange ?? 0) - 2.1) < 0.001)
        #expect(review.form == 6)
    }

    @Test func fitnessChangeNilWithoutSeries() {
        #expect(Self.build().fitnessChange == nil)
        #expect(Self.build().form == nil)
    }

    @Test func effortTotalAndRangeFromThePreviousThreeWeeks() {
        let rides = [Self.ride(1, day: 17, effort: 100), Self.ride(2, day: 19, effort: 60),
                     // The three weeks before: 100 each → range 75…125.
                     Self.ride(3, day: 10, effort: 100), Self.ride(4, day: 3, effort: 100),
                     Self.rideOn(5, Self.at(2026, 10, 27, 18), effort: 100)]
        let review = Self.build(rides: rides)
        #expect(review.effortTotal == 160)
        #expect(review.effortRange?.average == 100)
        #expect(review.effortStatus == .above)
    }

    @Test func recordsOfTheWeekAreFoundAmongRecentRides() {
        let old = Self.ride(1, day: 2, curve: [300: 250, 1200: 220])
        let strong = Self.ride(2, day: 18, curve: [300: 280, 1200: 215])
        let review = Self.build(rides: [old, strong])
        #expect(review.records.map(\.duration) == [300])
        #expect(review.records.first?.watts == 280)
    }

    // MARK: Texts

    @Test func allPlannedRidesGiveTheStrongWeekHeadline() {
        let rides = (0..<4).map { Self.ride($0, day: 16 + $0) }
        let planned = (0..<4).map { Self.planned(16 + $0, done: true) }
        #expect(Self.build(rides: rides, planned: planned).headline == "Starke Woche: alle 4 Einheiten gefahren")
    }

    @Test func partialWeekHeadlineNamesTheCount() {
        let planned = [Self.planned(16, done: true), Self.planned(17, done: true), Self.planned(19, done: false),
                       Self.planned(20, done: false)]
        let two = Self.build(rides: (0..<2).map { Self.ride($0, day: 16 + $0) }, planned: planned)
        #expect(two.headline == "Solide Woche: 2 von 4 Einheiten gefahren")
        let one = Self.build(rides: [Self.ride(1, day: 16)],
                             planned: [Self.planned(16, done: true), Self.planned(17, done: false),
                                       Self.planned(19, done: false), Self.planned(20, done: false)])
        #expect(one.headline == "Kurze Woche: 1 von 4 Einheiten gefahren")
    }

    @Test func unplannedWeekHeadlineCountsRides() {
        #expect(Self.build(rides: [Self.ride(1, day: 16)]).headline == "Gut drangeblieben: 1 Fahrt")
        #expect(Self.build(rides: [Self.ride(1, day: 16), Self.ride(2, day: 17)]).headline == "Gut drangeblieben: 2 Fahrten")
    }

    @Test func fitnessSentenceNamesChangeAndForm() {
        let points = [Self.point(Self.at(2026, 11, 15, 0), fitness: 41),
                      Self.point(Self.at(2026, 11, 22, 0), fitness: 43.1, form: 6)]
        let review = Self.build(rides: [Self.ride(1, day: 16)], points: points)
        #expect(review.sentences.contains("Fitness +2,1 – Form jetzt frisch (+6)"))
    }

    @Test func fitnessDropUsesMinusSign() {
        let points = [Self.point(Self.at(2026, 11, 15, 0), fitness: 41),
                      Self.point(Self.at(2026, 11, 22, 0), fitness: 39.6, form: 12)]
        let review = Self.build(rides: [Self.ride(1, day: 16)], points: points)
        #expect(review.sentences.contains("Fitness −1,4 – Form jetzt frisch (+12)"))
    }

    @Test func volumeSentenceComparesAgainstThePlan() {
        let review = Self.build(rides: [Self.ride(1, day: 16)], planned: [Self.planned(16, tss: 128, done: true)])
        #expect(review.sentences.first == "1:00 h gefahren, 64 TSS – 50 % vom Plan")
    }

    @Test func recordSentenceIsMentioned() {
        let old = Self.ride(1, day: 2, curve: [300: 250])
        let strong = Self.ride(2, day: 18, curve: [300: 280])
        #expect(Self.build(rides: [old, strong]).sentences.contains("Neue Bestleistung: 5 min mit 280 W"))
    }

    @Test func atMostThreeSentences() {
        let points = [Self.point(Self.at(2026, 11, 15, 0), fitness: 41), Self.point(Self.at(2026, 11, 22, 0), fitness: 43, form: 6)]
        let old = Self.ride(1, day: 2, curve: [300: 250])
        let strong = Self.ride(2, day: 18, effort: 90, curve: [300: 280])
        let review = Self.build(rides: [old, strong], planned: [Self.planned(18, done: true)], points: points)
        #expect(review.sentences.count == 3)
    }

    @Test func emptyWeekIsEncouragingNotShaming() {
        let review = Self.build(planned: [Self.planned(17, done: false), Self.planned(19, done: false)])
        #expect(review.isEmpty)
        #expect(review.headline == "Ruhewoche – Erholung zählt")
        #expect(review.sentences.count == 2)
        let joined = (review.headline + " " + review.sentences.joined(separator: " ")).lowercased()
        for bad in ["verpasst", "versagt", "leider", "schlecht", "faul"] { #expect(!joined.contains(bad), "\(bad)") }
    }

    @Test func recentWeeksAreNewestFirstAndStartAtTheFocusWeek() {
        let weeks = WeeklyReview.recent(count: 9, endingAt: Self.monday, rides: [Self.ride(1, day: 17)], planned: [],
                                        series: FitnessFreshness.Series(points: [], effortFactor: nil), ftp: Self.ftp,
                                        thresholdHeartRate: nil, heartRate: Self.hr, now: Self.at(2026, 11, 23, 9),
                                        calendar: Self.calendar())
        #expect(weeks.count == 9)
        #expect(weeks.first?.weekStart == Self.monday)
        #expect(weeks[1].weekStart == Self.at(2026, 11, 9, 0))
        #expect(weeks.first?.rideCount == 1)
    }
}
