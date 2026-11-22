import Foundation
import Testing
@testable import IndoorCoachKit

/// Winterlicht (docs/22, B3): Tageslänge nach Standardformel, Gewinn seit der Sonnenwende, Phasen, Zeitzonen.
@Suite("Winterlicht · Tageslänge")
struct DaylightTests {
    private func calendar(_ zone: String = "Europe/Berlin") -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12, minute: Int = 0, in c: Calendar) -> Date {
        c.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute))!
    }

    private func hours(_ seconds: TimeInterval) -> Double { seconds / 3600 }

    // MARK: Referenzwerte (Akzeptanz 1)

    @Test func lengthAtFiftyNorthOnTheWinterSolsticeIsAboutEightHours() {
        let c = calendar()
        let length = Daylight.length(on: day(2026, 12, 21, in: c), latitude: 50, calendar: c)
        #expect(length >= 7 * 3600 + 55 * 60 && length <= 8 * 3600 + 10 * 60, "\(hours(length)) h")
    }

    @Test func lengthAtFiftyNorthOnTheEquinoxIsJustOverTwelveHours() {
        let c = calendar()
        let length = Daylight.length(on: day(2027, 3, 20, in: c), latitude: 50, calendar: c)
        #expect(length >= 12 * 3600 && length <= 12 * 3600 + 20 * 60, "\(hours(length)) h")
    }

    @Test func summerSolsticeAtFiftyNorthIsAboutSixteenAndAHalfHours() {
        let c = calendar()
        let length = Daylight.length(on: day(2027, 6, 21, in: c), latitude: 50, calendar: c)
        #expect(hours(length) > 16.2 && hours(length) < 16.9, "\(hours(length)) h")
    }

    @Test func viennaAndZurichHaveLongerWinterDaysThanBerlin() {
        let c = calendar()
        let date = day(2026, 12, 21, in: c)
        let berlin = Daylight.length(on: date, latitude: 50, calendar: c)
        let vienna = Daylight.length(on: date, latitude: 48, calendar: c)
        let zurich = Daylight.length(on: date, latitude: 47, calendar: c)
        #expect(berlin < vienna && vienna < zurich)
    }

    @Test func timeOfDayDoesNotChangeTheLengthOfTheDay() {
        let c = calendar()
        let a = Daylight.length(on: day(2027, 1, 10, hour: 0, minute: 5, in: c), latitude: 50, calendar: c)
        let b = Daylight.length(on: day(2027, 1, 10, hour: 23, minute: 55, in: c), latitude: 50, calendar: c)
        #expect(a == b)
    }

    // MARK: Gewinn (Akzeptanz 2)

    @Test func gainRisesStrictlyFromTheDayAfterTheSolsticeToTheSummerSolstice() {
        let c = calendar()
        var previous = -Double.infinity
        var date = day(2026, 12, 22, in: c)
        let end = day(2027, 6, 20, in: c)
        var checked = 0
        while date <= end {
            let gain = Daylight.gainSinceSolstice(now: date, latitude: 50, calendar: c)
            #expect(gain > previous, "\(date.formatted(.iso8601.year().month().day()))")
            previous = gain
            checked += 1
            date = c.date(byAdding: .day, value: 1, to: date)!
        }
        #expect(checked == 181)
    }

    @Test func gainIsZeroOnTheSolsticeAndPositiveAfterwards() {
        let c = calendar()
        #expect(Daylight.gainSinceSolstice(now: day(2026, 12, 21, in: c), latitude: 50, calendar: c) == 0)
        let jan = Daylight.gainSinceSolstice(now: day(2027, 1, 14, in: c), latitude: 50, calendar: c)
        #expect(jan / 60 > 20 && jan / 60 < 45, "\(jan / 60) min")
    }

    @Test func goalIsAboutFourHoursLongerThanTheSolstice() {
        let c = calendar()
        let solstice = Daylight.length(on: day(2026, 12, 21, in: c), latitude: 50, calendar: c)
        let goal = Daylight.length(on: day(2027, 3, 21, in: c), latitude: 50, calendar: c)
        #expect(hours(goal - solstice) > 4.0 && hours(goal - solstice) < 4.3)
    }

    // MARK: Phasen (Akzeptanz 3)

    @Test func phasesBeforeAtAndAfterTheSolstice() {
        let c = calendar()
        #expect(Daylight.phase(now: day(2026, 12, 12, in: c), latitude: 50, calendar: c) == .beforeSolstice(days: 9))
        #expect(Daylight.phase(now: day(2026, 12, 20, in: c), latitude: 50, calendar: c) == .beforeSolstice(days: 1))
        #expect(Daylight.phase(now: day(2026, 12, 21, in: c), latitude: 50, calendar: c) == .solstice)
        guard case .lengthening(let gain) = Daylight.phase(now: day(2027, 1, 14, in: c), latitude: 50, calendar: c) else {
            Issue.record("Nach der Sonnenwende erwartet")
            return
        }
        #expect(gain > 20 && gain < 45)
    }

    @Test func equinoxStartsOnTheTwentiethOfMarch() {
        let c = calendar()
        guard case .lengthening = Daylight.phase(now: day(2027, 3, 19, in: c), latitude: 50, calendar: c) else {
            Issue.record("19.3. ist noch Winterlicht")
            return
        }
        #expect(Daylight.phase(now: day(2027, 3, 20, in: c), latitude: 50, calendar: c) == .afterEquinox)
        #expect(Daylight.phase(now: day(2027, 5, 1, in: c), latitude: 50, calendar: c) == .afterEquinox)
    }

    @Test func autumnCountsDownToTheNextSolstice() {
        let c = calendar()
        #expect(Daylight.phase(now: day(2026, 11, 21, in: c), latitude: 50, calendar: c) == .beforeSolstice(days: 30))
        #expect(Daylight.phase(now: day(2026, 11, 1, in: c), latitude: 50, calendar: c) == .beforeSolstice(days: 50))
    }

    @Test func theDayChangesInTheLocalZone() {
        // 20.12.2026, 23:30 UTC: in Berlin schon der 21.12. (Wintersonnenwende), in London und New York noch der 20.12.
        let utc = calendar("UTC")
        let instant = day(2026, 12, 20, hour: 23, minute: 30, in: utc)
        let berlin = calendar("Europe/Berlin"), london = calendar("Europe/London"), newYork = calendar("America/New_York")
        #expect(Daylight.phase(now: instant, latitude: 50, calendar: berlin) == .solstice)
        #expect(Daylight.phase(now: instant, latitude: 50, calendar: london) == .beforeSolstice(days: 1))
        #expect(Daylight.phase(now: instant, latitude: 50, calendar: newYork) == .beforeSolstice(days: 1))
    }

    @Test func leapYearDoesNotShiftTheSolstice() {
        let c = calendar()
        #expect(Daylight.phase(now: day(2027, 12, 21, in: c), latitude: 50, calendar: c) == .solstice)
        // Silvester 2027 → Neujahr 2028 (Schaltjahr): der Gewinn wächst über den Jahreswechsel weiter.
        let a = Daylight.gainSinceSolstice(now: day(2027, 12, 31, in: c), latitude: 50, calendar: c)
        let b = Daylight.gainSinceSolstice(now: day(2028, 1, 1, in: c), latitude: 50, calendar: c)
        #expect(b > a)
        #expect(Daylight.phase(now: day(2028, 3, 20, in: c), latitude: 50, calendar: c) == .afterEquinox)
    }

    // MARK: Zeitzone → Breitengrad (E3)

    @Test func latitudeComesFromTheTimeZoneWithoutLocation() {
        func lat(_ id: String) -> Double { Daylight.latitude(for: TimeZone(identifier: id)!) }
        #expect(lat("Europe/Berlin") == 50)
        #expect(lat("Europe/Vienna") == 48)
        #expect(lat("Europe/Zurich") == 47)
        #expect(lat("Europe/London") == 50)
        #expect(lat("America/New_York") == 50)
    }

    @Test func footnoteNamesTheRegionAndNeverClaimsALocation() {
        #expect(Daylight.footnote(for: TimeZone(identifier: "Europe/Berlin")!) == "Berechnet für die Mitte Deutschlands (50° N).")
        #expect(Daylight.footnote(for: TimeZone(identifier: "Europe/Vienna")!) == "Berechnet für Österreich (48° N).")
        #expect(Daylight.footnote(for: TimeZone(identifier: "Europe/Zurich")!) == "Berechnet für die Schweiz (47° N).")
        let other = Daylight.footnote(for: TimeZone(identifier: "Europe/London")!)
        #expect(other.contains("50° N") && other.contains("Näherung"))
    }

    // MARK: Randfälle: Süd, Pol, Äquator

    @Test func southernAndExtremeLatitudesStayFinite() {
        let c = calendar("UTC")
        for latitude in [-89.0, -66.6, -34.0, 0.0, 66.6, 80.0, 89.0] {
            var date = day(2026, 1, 1, in: c)
            for _ in 0..<366 {
                let length = Daylight.length(on: date, latitude: latitude, calendar: c)
                #expect(length.isFinite && length >= 0 && length <= 86_400, "lat \(latitude)")
                date = c.date(byAdding: .day, value: 1, to: date)!
            }
        }
    }

    @Test func polarNightAndMidnightSunAreClamped() {
        let c = calendar("UTC")
        #expect(Daylight.length(on: day(2026, 12, 21, in: c), latitude: 80, calendar: c) == 0)
        #expect(Daylight.length(on: day(2027, 6, 21, in: c), latitude: 80, calendar: c) == 86_400)
    }

    @Test func southernSummerIsLongInDecemberAndMirrorsTheNorth() {
        let c = calendar("UTC")
        let sydney = Daylight.length(on: day(2026, 12, 21, in: c), latitude: -34, calendar: c)
        #expect(hours(sydney) > 14 && hours(sydney) < 14.8)
        let north = Daylight.length(on: day(2026, 12, 21, in: c), latitude: 50, calendar: c)
        let south = Daylight.length(on: day(2027, 6, 21, in: c), latitude: -50, calendar: c)
        #expect(abs(north - south) < 4 * 60)
    }

    @Test func equatorIsAlwaysAboutTwelveHours() {
        let c = calendar("UTC")
        for (m, d) in [(1, 15), (3, 20), (6, 21), (9, 22), (12, 21)] {
            let length = Daylight.length(on: day(2027, m, d, in: c), latitude: 0, calendar: c)
            #expect(hours(length) > 11.95 && hours(length) < 12.25, "\(m)/\(d)")
        }
    }

    @Test func displayedGainNeverGoesNegative() {
        // Auf der Südhalbkugel wäre der Gewinn nach dem 21.12. negativ; die Anzeige rundet bei 0 ab.
        let c = calendar("UTC")
        guard case .lengthening(let gain) = Daylight.phase(now: day(2027, 2, 1, in: c), latitude: -34, calendar: c) else {
            Issue.record("Der Kalender legt die Phase fest")
            return
        }
        #expect(gain >= 0)
    }

    // MARK: Texte

    @Test func linesFollowThePhase() {
        #expect(Daylight.line(for: .beforeSolstice(days: 9)) == "Noch 9 Tage bis zur Wintersonnenwende. Danach wird jeder Tag ein bisschen heller.")
        #expect(Daylight.line(for: .beforeSolstice(days: 1)).hasPrefix("Noch 1 Tag bis zur Wintersonnenwende."))
        #expect(Daylight.line(for: .solstice) == "Heute ist Wintersonnenwende, der kürzeste Tag des Jahres. Ab morgen geht’s bergauf.")
        #expect(Daylight.line(for: .lengthening(gainMinutes: 34)) == "+34 min Tageslicht seit der Wintersonnenwende")
        #expect(Daylight.line(for: .afterEquinox) == "Die Tage sind jetzt länger als die Nächte. Frühling!")
    }

    @Test func tinyGainReadsAsWordsNotAsPlusZero() {
        let line = Daylight.line(for: .lengthening(gainMinutes: 0))
        #expect(!line.contains("+0"))
        #expect(line.contains("länger"))
    }

    @Test func chipIsShortAndSpokenLineSaysMinutes() {
        #expect(Daylight.chip(for: .lengthening(gainMinutes: 34)) == "+34 min Licht")
        #expect(Daylight.chip(for: .beforeSolstice(days: 9)).contains("9"))
        #expect(Daylight.spokenLine(for: .lengthening(gainMinutes: 34)) == "34 Minuten mehr Tageslicht seit der Wintersonnenwende")
        #expect(Daylight.spokenLine(for: .lengthening(gainMinutes: 1)).hasPrefix("1 Minute "))
    }

    @Test func goalLineCountsDaysAndLight() {
        let c = calendar()
        let now = day(2026, 12, 25, in: c), goal = day(2027, 3, 21, in: c)
        let line = Daylight.goalLine(now: now, goal: goal, latitude: 50, calendar: c)
        #expect(line?.hasPrefix("Bis zu deinem Ziel am 21. März: noch 86 Tage. Dann hast du ") == true, "\(line ?? "nil")")
        #expect(line?.contains(" h ") == true && line?.hasSuffix("mehr Licht als heute.") == true)
        #expect(Daylight.goalLine(now: goal, goal: goal, latitude: 50, calendar: c) == nil)
        #expect(Daylight.goalLine(now: day(2027, 4, 1, in: c), goal: goal, latitude: 50, calendar: c) == nil)
    }

    @Test func sunFractionRisesFromTheSolsticeToTheGoal() {
        let c = calendar()
        let goal = day(2027, 3, 21, in: c)
        #expect(Daylight.sunFraction(now: day(2026, 11, 15, in: c), goal: goal, latitude: 50, calendar: c) == 0)
        #expect(Daylight.sunFraction(now: day(2026, 12, 21, in: c), goal: goal, latitude: 50, calendar: c) == 0)
        let mid = Daylight.sunFraction(now: day(2027, 2, 1, in: c), goal: goal, latitude: 50, calendar: c)
        #expect(mid > 0.1 && mid < 0.7)
        #expect(Daylight.sunFraction(now: goal, goal: goal, latitude: 50, calendar: c) > 0.99)
        #expect(Daylight.sunFraction(now: day(2027, 5, 1, in: c), goal: goal, latitude: 50, calendar: c) == 1)
    }

    @Test func lengthSeriesCoversTheWindowForTheChart() {
        let c = calendar()
        let from = day(2026, 11, 1, in: c), to = day(2027, 3, 21, in: c)
        let series = Daylight.lengthSeries(from: from, to: to, latitude: 50, stepDays: 7, calendar: c)
        #expect(series.count > 20)
        #expect(series.first?.date == from)
        #expect(series.last?.date == to)   // der Zieltag gehört immer dazu
        let shortest = series.min { $0.hours < $1.hours }
        #expect(shortest != nil && abs(shortest!.date.timeIntervalSince(day(2026, 12, 21, in: c))) < 8 * 86_400)
    }
}
