import Foundation
import Testing
@testable import IndoorCoachKit

private let berlin: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Berlin")!
    c.firstWeekday = 2
    c.minimumDaysInFirstWeek = 4
    return c
}()

private func at(_ y: Int, _ m: Int, _ d: Int) -> Date { berlin.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }

@Suite("Winterlicht · Südhalbkugel und Sommer")
struct DaylightSouthTests {
    @Test func southernZonesShowNoWinterlight() {
        for id in ["Australia/Sydney", "Australia/Perth", "Pacific/Auckland", "America/Sao_Paulo", "Africa/Johannesburg",
                   "America/Argentina/Buenos_Aires", "America/Santiago"] {
            let zone = TimeZone(identifier: id)!
            #expect(Daylight.isSouthernHemisphere(zone), "\(id)")
            #expect(!Daylight.showsWinterlight(for: zone), "\(id)")
        }
        for id in ["Europe/Berlin", "Europe/Vienna", "America/New_York", "Asia/Tokyo", "Pacific/Honolulu", "Europe/London"] {
            #expect(Daylight.showsWinterlight(for: TimeZone(identifier: id)!), "\(id)")
        }
    }

    @Test func summerStartsOnTwentyFirstOfJuneWithoutSpringSentence() {
        #expect(Daylight.phase(now: at(2027, 6, 20), latitude: 50, calendar: berlin) == .afterEquinox)
        #expect(Daylight.phase(now: at(2027, 6, 21), latitude: 50, calendar: berlin) == .summer)
        #expect(Daylight.phase(now: at(2027, 7, 31), latitude: 50, calendar: berlin) == .summer)
        guard case .beforeSolstice = Daylight.phase(now: at(2027, 8, 1), latitude: 50, calendar: berlin) else {
            Issue.record("Ab August Countdown")
            return
        }
        #expect(!Daylight.line(for: .summer).contains("Frühling"))
        #expect(!Daylight.chip(for: .summer).isEmpty)
        #expect(Daylight.sunFraction(now: at(2027, 7, 1), goal: at(2027, 3, 21), latitude: 50, calendar: berlin) == 1)
    }
}

@Suite("Comeback-Lücke (gemeinsamer Helfer)")
struct ComebackGapHelperTests {
    @Test func gapCountsCalendarDaysToTheLatestEarlierActivity() {
        let acts = [at(2026, 12, 1), at(2026, 12, 5)]
        #expect(Comeback.gapDays(before: at(2026, 12, 20), in: acts, calendar: berlin) == 15)
        #expect(Comeback.gapDays(before: at(2026, 12, 5), in: acts, calendar: berlin) == 4) // gleiche Zeit zählt nicht als früher
        #expect(Comeback.gapDays(before: at(2026, 11, 1), in: acts, calendar: berlin) == nil)
    }

    @Test func detectorCountsStrengthSessionsLikeTheCard() {
        func ride(_ id: Int, _ date: Date) -> RideSummary {
            RideSummary(id: id, name: "Fahrt", sportType: "VirtualRide", startDate: date, movingTime: 3600, distance: 30_000,
                        averageWatts: 150, weightedAverageWatts: 160, trainer: true)
        }
        var input = MomentInput(season: "2026", seasonStart: at(2026, 11, 1), rides: [ride(1, at(2026, 11, 1)), ride(2, at(2026, 12, 17))],
                                trophies: [], challenges: [], weeks: [], calendar: berlin)
        let now = at(2026, 12, 18)
        #expect(MomentDetector.moments(forRide: 2, input: input, now: now).contains { $0.kind == .comeback })
        input.otherActivityDates = [at(2026, 12, 10)]
        #expect(!MomentDetector.moments(forRide: 2, input: input, now: now).contains { $0.kind == .comeback })
    }
}

@Suite("ShareText · Fix-Runde")
struct ShareTextFixTests {
    @Test func polarNightSurvivesButBrandsAreStripped() {
        #expect(ShareText.neutral("Polar-Nacht Fahrt") == "Polar-Nacht Fahrt")
        #expect(ShareText.neutral("Polar Flow Fahrt") == "Fahrt")
        #expect(ShareText.neutral("Intervals.icu · Grundlage") == "Grundlage")
        #expect(ShareText.neutral("Intervals ICU Grundlage") == "Grundlage")
        #expect(ShareText.neutral("Apple Watch Fahrt") == "Fahrt")
        #expect(ShareText.neutral("Von Strava importiert") == "Von importiert")
    }

    @Test func pauseDetailOnlyWithValues() {
        let m = Moment(id: "comeback-1", kind: .comeback, date: .now, headline: "Du bist zurück",
                       detail: "Nach 12 Tagen Pause wieder im Sattel.", rideID: 1)
        #expect(ShareText.detail(for: m, showValues: false) == nil)
        #expect(ShareText.detail(for: m, showValues: true) == "Nach 12 Tagen Pause wieder im Sattel.")
    }

    @Test func nameOnlyWhenSwitchedOn() {
        #expect(ShareText.shareName("Sabine", show: false) == nil)
        #expect(ShareText.shareName("  Sabine ", show: true) == "Sabine")
        #expect(ShareText.shareName("  ", show: true) == nil)
        #expect(ShareText.shareName(nil, show: true) == nil)
    }

    @Test func staleShareFilesAreRemovedButFreshOnesStay() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["IndoorCoach-alt.png", "IndoorCoach-neu.png", "IndoorCoach-jetzt.png", "fremd.png"] {
            try Data([1]).write(to: dir.appendingPathComponent(name))
        }
        let old = Date(timeIntervalSinceNow: -3600)
        for name in ["IndoorCoach-alt.png", "IndoorCoach-jetzt.png", "fremd.png"] {
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: dir.appendingPathComponent(name).path)
        }
        let removed = ShareImageRenderer.removeStale(in: dir, keeping: "IndoorCoach-jetzt.png")
        #expect(removed == 1)
        let left = Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
        #expect(left == ["IndoorCoach-neu.png", "IndoorCoach-jetzt.png", "fremd.png"])
    }

    @Test func whySaveHintExplainsTheDisabledButton() {
        #expect(WhyNote.saveHint(draft: "", hasSaved: false) != nil)
        #expect(WhyNote.saveHint(draft: "Mein Ziel: ", hasSaved: false) != nil)
        #expect(WhyNote.saveHint(draft: "Im Mai die RTF", hasSaved: false) == nil)
        #expect(WhyNote.saveHint(draft: "", hasSaved: true) == nil)
    }

    @Test func postcardFirstLineIsTheFirstSentence() {
        #expect(Postcards.firstLine("Hier pfeift der Wind. Der Rest folgt.") == "Hier pfeift der Wind.")
        #expect(Postcards.firstLine("Ohne Punkt") == "Ohne Punkt")
    }
}
