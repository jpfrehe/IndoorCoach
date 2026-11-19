import Foundation
import Testing
@testable import IndoorCoachKit

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return c
}()

private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }

private func check(_ date: Date, hr: Double, ref: Int = 140, source: WarmupCheck.Source = .measured, valid: Bool = true) -> WarmupCheck {
    WarmupCheck(date: date, refWatts: ref, hrMean: valid ? hr : nil, valid: valid, reason: valid ? nil : "x", source: source)
}

private func resting(_ from: Date, days: Int, value: Double) -> [HealthDaily] {
    (0..<days).map { i in
        HealthDaily(date: cal.date(byAdding: .day, value: i, to: from)!, metric: .restingHR, value: value,
                    source: HealthSourceRef(name: "Apple Watch", bundleID: "com.apple.health"))
    }
}

private func ride(_ id: Int, _ date: Date, watts: Double, hr: Double) -> RideSummary {
    RideSummary(id: id, name: "R", sportType: "VirtualRide", startDate: date, movingTime: 3600, distance: 30_000,
                averageWatts: watts, weightedAverageWatts: watts, averageHeartrate: hr, trainer: true)
}

private func make(checks: [WarmupCheck] = [], dailies: [HealthDaily] = [], rides: [RideSummary] = [],
                  strength: [Date] = [], now: Date = day(2027, 1, 20)) -> HeartInWinterArc {
    HeartInWinterArc.make(from: day(2026, 11, 1), now: now, refWatts: 140, checks: checks, restingDailies: dailies,
                          rides: rides, ftp: 250, strengthStarts: strength, calendar: cal)
}

@Suite("Dein Herz im Winter Arc")
struct HeartInWinterArcTests {
    @Test func warmupMedianPerMonthNeedsTwoChecksPerMonth() {
        let checks = [check(day(2026, 11, 5), hr: 126), check(day(2026, 11, 12), hr: 124), check(day(2026, 11, 20), hr: 128),
                      check(day(2026, 12, 3), hr: 120),                                   // only one in December: not enough
                      check(day(2027, 1, 4), hr: 114), check(day(2027, 1, 11), hr: 112)]
        let h = make(checks: checks)
        let months = h.warmup?.months ?? []
        #expect(months.map(\.value) == [126, 113])
        #expect(months.map(\.samples) == [3, 2])
        #expect(h.warmup?.sourceText == "gemessen")
    }

    @Test func warmupIgnoresInvalidOtherReferenceAndBeforeStart() {
        let checks = [check(day(2026, 10, 20), hr: 140), check(day(2026, 10, 25), hr: 140),     // before the arc
                      check(day(2026, 11, 5), hr: 130, ref: 150), check(day(2026, 11, 6), hr: 130, ref: 150),   // other reference
                      check(day(2026, 11, 7), hr: 0, valid: false), check(day(2026, 11, 8), hr: 0, valid: false)]
        #expect(make(checks: checks).warmup == nil)
    }

    @Test func warmupWithAssumedPowerIsLabelledErg() {
        let checks = [check(day(2026, 11, 5), hr: 126), check(day(2026, 11, 12), hr: 124, source: .assumedERG),
                      check(day(2027, 1, 4), hr: 114), check(day(2027, 1, 11), hr: 112)]
        #expect(make(checks: checks).warmup?.sourceText == "angenommen (ERG)")
    }

    @Test func oneMonthAloneIsNoComparison() {
        let checks = [check(day(2026, 11, 5), hr: 126), check(day(2026, 11, 12), hr: 124)]
        let h = make(checks: checks, now: day(2026, 11, 20))
        #expect(h.warmup == nil)
        #expect(h.sentence == nil)
        #expect(h.seasonLines.isEmpty)
    }

    @Test func restingBaseNeedsTenDaysPerMonthAndNamesTheSource() {
        let dailies = resting(day(2026, 11, 1), days: 20, value: 58) + resting(day(2026, 12, 1), days: 5, value: 56)
            + resting(day(2027, 1, 1), days: 15, value: 53)
        let h = make(dailies: dailies)
        #expect(h.resting?.months.map(\.value) == [58, 53])
        #expect(h.resting?.sourceText == "Apple Health · Apple Watch")
    }

    @Test func efficiencyPerMonthFromEnduranceRides() {
        let rides = [ride(1, day(2026, 11, 3), watts: 150, hr: 125), ride(2, day(2026, 11, 10), watts: 150, hr: 125),
                     ride(3, day(2027, 1, 5), watts: 150, hr: 115), ride(4, day(2027, 1, 12), watts: 150, hr: 115)]
        let ef = make(rides: rides).efficiency
        #expect(ef?.months.count == 2)
        #expect(abs((ef?.first?.value ?? 0) - 1.2) < 0.001)
        #expect((ef?.last?.value ?? 0) > (ef?.first?.value ?? 9))
    }

    @Test func strengthCountsPerMonthAndTotal() {
        let h = make(strength: [day(2026, 11, 3), day(2026, 11, 20), day(2026, 12, 2), day(2026, 10, 30)])
        #expect(h.strength.map(\.value) == [2, 1])
        #expect(h.strengthTotal == 3)
        #expect(h.seasonLines.contains("Kraft-Winter: 3 Einheiten"))
        #expect(make(strength: [day(2026, 11, 3)]).seasonLines == ["Kraft-Winter: 1 Einheit"])
        #expect(make().strengthTotal == 0)
        #expect(make().seasonLines.isEmpty)
    }

    @Test func sentenceOnlyWhenTheDataShowsIt() {
        let falling = [check(day(2026, 11, 5), hr: 126), check(day(2026, 11, 12), hr: 124),
                       check(day(2027, 1, 4), hr: 114), check(day(2027, 1, 11), hr: 112)]
        let rising = [check(day(2026, 11, 5), hr: 114), check(day(2026, 11, 12), hr: 112),
                      check(day(2027, 1, 4), hr: 126), check(day(2027, 1, 11), hr: 124)]
        let calmer = resting(day(2026, 11, 1), days: 20, value: 58) + resting(day(2027, 1, 1), days: 15, value: 53)
        let same = resting(day(2026, 11, 1), days: 20, value: 58) + resting(day(2027, 1, 1), days: 15, value: 58)
        #expect(make(checks: falling, dailies: calmer).sentence == "Gleiche Watt, weniger Puls, ruhigeres Herz.")
        #expect(make(checks: falling, dailies: same).sentence == "Gleiche Watt, weniger Puls.")
        #expect(make(dailies: calmer).sentence == "Ruhigeres Herz in Ruhe.")
        #expect(make(checks: rising, dailies: same).sentence == nil)
        #expect(make(checks: rising, dailies: calmer).sentence == "Ruhigeres Herz in Ruhe.")
        #expect(make().sentence == nil)
    }

    @Test func seasonLinesOnlyForAvailableFigures() {
        let checks = [check(day(2026, 11, 5), hr: 124), check(day(2026, 11, 12), hr: 124),
                      check(day(2027, 1, 4), hr: 113), check(day(2027, 1, 11), hr: 113)]
        let dailies = resting(day(2026, 11, 1), days: 20, value: 58) + resting(day(2027, 1, 1), days: 15, value: 53)
        let h = make(checks: checks, dailies: dailies, strength: (0..<14).map { day(2026, 11, 2 + $0) })
        #expect(h.seasonLines == ["Puls bei 140 W: 124 → 113", "Ruhepuls 58 → 53", "Kraft-Winter: 14 Einheiten"])
        #expect(make(dailies: dailies).seasonLines == ["Ruhepuls 58 → 53"])
    }

    @Test func seasonSummaryCarriesTheLines() {
        let now = day(2027, 1, 20)
        let status = WinterArc.status(start: day(2026, 11, 1), goal: day(2027, 3, 21), today: now, startCTL: 24, currentCTL: 34,
                                      bestCTLSinceStart: 35, targetCTL: 44, calendar: cal)
        let s = SeasonSummary.make(status: status, challenges: [], rides: [], name: "", now: now, calendar: cal,
                                   heartLines: ["Ruhepuls 58 → 53"])
        #expect(s.heartLines == ["Ruhepuls 58 → 53"])
        #expect(SeasonSummary.make(status: status, challenges: [], rides: [], name: "", now: now, calendar: cal).heartLines.isEmpty)
    }
}
