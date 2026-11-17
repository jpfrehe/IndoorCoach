import Foundation
import Testing
@testable import IndoorCoachKit

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return c
}()

private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: 18))!
}

private func ride(id: Int = 1, minutes: Int = 60, on date: Date = day(2026, 11, 10), np: Double? = nil, hr: Double? = nil,
                  pe: Int? = nil, preferPE: Bool = false, strava: Double? = nil) -> RideSummary {
    var r = RideSummary(id: id, name: "R\(id)", sportType: "VirtualRide", startDate: date, movingTime: minutes * 60,
                        distance: 30_000, averageWatts: np.map { $0 * 0.95 }, weightedAverageWatts: np,
                        averageHeartrate: hr, trainer: true)
    r.perceivedExertion = pe
    r.preferPerceivedExertion = preferPE
    r.stravaRelativeEffort = strava
    return r
}

// MARK: - S7 Relative Effort

@Suite("Relative Effort")
struct RelativeEffortTests {
    let hr = RelativeEffort.HeartRateProfile(resting: 50, max: 190)

    @Test func trimpMagnitudesAreStravaLike() {
        // 1 h easy (HRr = 0.5) ≈ 50, 1 h near threshold (HRr = 0.85) ≈ 165 (Banister TRIMP).
        let easy = RelativeEffort.estimate(for: ride(hr: 120), heartRate: hr)
        let hard = RelativeEffort.estimate(for: ride(hr: 169), heartRate: hr)
        #expect(easy.source == .heartRate)
        #expect((40...90).contains(easy.value!))
        #expect((140...240).contains(hard.value!))
        #expect(hard.value! > easy.value! * 2)
    }

    @Test func scalesWithDuration() {
        let one = RelativeEffort.estimate(for: ride(minutes: 60, hr: 140), heartRate: hr).value!
        let two = RelativeEffort.estimate(for: ride(minutes: 120, hr: 140), heartRate: hr).value!
        #expect(abs(two - 2 * one) < 0.01)
    }

    @Test func perceivedExertionFallbackWithoutHeartRate() {
        let e = RelativeEffort.estimate(for: ride(pe: 7), heartRate: hr)
        #expect(e.source == .perceivedExertion)
        let e3 = RelativeEffort.estimate(for: ride(pe: 3), heartRate: hr).value!
        #expect(e.value! > e3)
    }

    @Test func priorityPreferredPEThenStravaThenHeartRate() {
        #expect(RelativeEffort.estimate(for: ride(hr: 140, pe: 9, preferPE: true, strava: 80), heartRate: hr).source == .perceivedExertion)
        #expect(RelativeEffort.estimate(for: ride(hr: 140, pe: 9, strava: 80), heartRate: hr).source == .strava)
        #expect(RelativeEffort.estimate(for: ride(hr: 140, pe: 9), heartRate: hr).source == .heartRate)
        #expect(RelativeEffort.estimate(for: ride(), heartRate: hr).value == nil)
    }

    @Test func implausibleInputsAreRejected() {
        #expect(RelativeEffort.estimate(for: ride(hr: 40), heartRate: hr).value == nil) // below resting
        #expect(RelativeEffort.estimate(for: ride(pe: 0), heartRate: hr).value == nil)
        #expect(RelativeEffort.estimate(for: ride(pe: 11), heartRate: hr).value == nil)
        #expect(RelativeEffort.HeartRateProfile(resting: 60, max: 55).isValid == false)
    }

    @Test func weeklyRangeFromThreePreviousWeeks() {
        let range = RelativeEffort.weeklyRange(previousWeeks: [200, 260, 230])!
        #expect(abs(range.average - 230) < 0.001)
        #expect(range.lower < 230 && range.upper > 230)
        #expect(range.status(for: 150) == .below)
        #expect(range.status(for: 230) == .within)
        #expect(range.status(for: 400) == .above)
        #expect(RelativeEffort.weeklyRange(previousWeeks: [0, 0, 0]) == nil)
    }
}

// MARK: - Profile migration

@Suite("Profile migration")
struct ProfileMigrationTests {
    @Test func decodesProfileSavedBeforeTheWinterArcFields() throws {
        let old = #"{"name":"","ftp":281,"weightKg":72,"goal":"Ötztaler","weeklyHours":6,"trainingDays":[1,3],"#
            + #""longestSessionMinutes":120,"preferredStartHour":6,"preferredStartMinute":15,"notes":"","planHorizonDays":14,"#
            + #""model":"claude-sonnet-5-5"}"#
        let p = try JSONDecoder().decode(AthleteProfile.self, from: Data(old.utf8))
        #expect(p.ftp == 281 && p.weeklyHours == 6 && p.trainingDays == [1, 3] && p.planHorizonDays == 14)
        #expect(p.restingHeartRate == 50 && p.maxHeartRate == nil && p.targetCTL == nil)
    }

    @Test func roundTripsNewFields() throws {
        var p = AthleteProfile()
        p.restingHeartRate = 46; p.maxHeartRate = 188; p.targetCTL = 72; p.arcStart = day(2026, 11, 1)
        let back = try JSONDecoder().decode(AthleteProfile.self, from: JSONEncoder().encode(p))
        #expect(back == p)
    }

    @Test func maxHeartRateFallsBackToThreshold() {
        var p = AthleteProfile()
        #expect(p.heartRateProfile.max == 190)
        p.thresholdHeartRate = 170
        #expect(p.heartRateProfile.max == 189) // LTHR / 0.9
        p.maxHeartRate = 195
        #expect(p.heartRateProfile.max == 195)
    }
}

// MARK: - S8 Fitness & Freshness

@Suite("Fitness & Freshness")
struct FitnessFreshnessTests {
    let hr = RelativeEffort.HeartRateProfile(resting: 50, max: 190)

    @Test func fitsTSSPerRelativeEffortFromRidesWithBoth() {
        // 12 rides where TSS ≈ 0.8 × RE, plus one HR-only ride.
        var rides: [RideSummary] = (0..<12).map { i in ride(id: i, minutes: 60 + i * 5, np: 200, hr: 140) }
        rides.append(ride(id: 99, minutes: 60, hr: 140))
        let k = FitnessFreshness.effortToLoadFactor(rides: rides, ftp: 250, heartRate: hr)
        #expect(k != nil)
        let load = FitnessFreshness.load(for: rides.last!, ftp: 250, heartRate: hr, thresholdHeartRate: nil, effortFactor: k)
        #expect(load.source == .relativeEffort)
        let re = RelativeEffort.estimate(for: rides.last!, heartRate: hr).value!
        #expect(abs(load.value - re * k!) < 0.001)
    }

    @Test func needsTenRidesForTheFit() {
        let rides = (0..<9).map { i in ride(id: i, np: 200, hr: 140) }
        #expect(FitnessFreshness.effortToLoadFactor(rides: rides, ftp: 250, heartRate: hr) == nil)
    }

    @Test func powerWinsOverEffort() {
        let load = FitnessFreshness.load(for: ride(np: 250, hr: 150), ftp: 250, heartRate: hr, thresholdHeartRate: nil, effortFactor: 0.5)
        #expect(load.source == .power)
        #expect(abs(load.value - 100) < 0.001)
    }

    @Test func seriesAndSevenDayDelta() {
        let start = day(2026, 9, 1)
        let rides = (0..<70).map { i in ride(id: i, on: cal.date(byAdding: .day, value: i, to: start)!, np: 200) }
        let s = FitnessFreshness.series(rides: rides, ftp: 250, heartRate: hr, thresholdHeartRate: nil,
                                        from: start, to: day(2026, 11, 9), calendar: cal)
        #expect(s.points.count == 70)
        #expect(s.points.last!.fitness > s.points.first!.fitness)
        #expect(s.fitnessDelta7 > 0)
        #expect(abs(s.points.last!.form - (s.points[s.points.count - 2].fitness - s.points[s.points.count - 2].fatigue)) < 0.001)
        #expect(s.points(in: .days30).count == 30)
    }
}

// MARK: - S9 Winter Arc

@Suite("Winter Arc")
struct WinterArcTests {
    let start = day(2026, 11, 1)
    let goal = day(2027, 3, 21)

    func arc(today: Date, ctl: [Double], targetCTL: Double? = nil, weeklyHours: [Double] = [], budget: Double = 5) -> WinterArc.Status {
        WinterArc.status(start: start, goal: goal, today: today, startCTL: 40, currentCTL: ctl.last ?? 40,
                         bestCTLSinceStart: ctl.max() ?? 40, targetCTL: targetCTL, weeklyHours: weeklyHours,
                         weeklyBudgetHours: budget, calendar: cal)
    }

    @Test func defaultTargetIsAmbitiousButReachable() {
        #expect(WinterArc.defaultTarget(startCTL: 40) == 55)   // max(+15, ×1.35=54)
        #expect(WinterArc.defaultTarget(startCTL: 60) == 81)
    }

    @Test func levelsFollowProgressAndNeverDrop() {
        let s1 = arc(today: day(2026, 12, 1), ctl: [40, 47])      // 7/15 ≈ 47 % → level 5
        #expect(s1.level.number == 5)
        let s2 = arc(today: day(2026, 12, 8), ctl: [40, 47, 43])  // dropped, best stays 47
        #expect(s2.level.number == 5)
        let s3 = arc(today: day(2027, 3, 1), ctl: [40, 56])
        #expect(s3.level.number == 10)
        #expect(s3.level.name == "Frühlingsform")
        #expect(WinterArc.levels.count == 10)
        #expect(WinterArc.levels.first!.name == "Erster Frost")
    }

    @Test func onTrackCompareswithLinearPace() {
        // Halfway through the season the pace line is at 47.5 (40 → 55).
        let mid = cal.date(byAdding: .day, value: 70, to: start)!
        #expect(arc(today: mid, ctl: [40, 47.5]).pace == .onTrack)
        #expect(arc(today: mid, ctl: [40, 52]).pace == .ahead)
        #expect(arc(today: mid, ctl: [40, 42]).pace == .behind)
    }

    @Test func progressDaysAndStreak() {
        let s = arc(today: day(2026, 12, 1), ctl: [40, 47], weeklyHours: [5, 4.5, 2, 4.2, 5.5])
        #expect(s.daysTotal == 140)
        #expect(s.daysLeft == 110)
        #expect(abs(s.seasonFraction - 30.0 / 140) < 0.01)
        #expect(s.streakWeeks == 2) // last two weeks ≥ 80 % of 5 h; the 2 h week broke the streak
        #expect((0...1).contains(s.levelProgress))
    }

    @Test func defaultSeasonDates() {
        let (s, g) = WinterArc.defaultSeason(containing: day(2026, 11, 17), calendar: cal)
        #expect(cal.dateComponents([.year, .month, .day], from: s) == DateComponents(year: 2026, month: 11, day: 1))
        #expect(cal.dateComponents([.year, .month, .day], from: g) == DateComponents(year: 2027, month: 3, day: 21))
        let (s2, _) = WinterArc.defaultSeason(containing: day(2027, 2, 10), calendar: cal)
        #expect(cal.component(.year, from: s2) == 2026)
    }
}
