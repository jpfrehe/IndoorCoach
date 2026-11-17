import Foundation
import Testing
@testable import IndoorCoachKit

private var utc: Calendar { var c = Calendar(identifier: .iso8601); c.timeZone = TimeZone(identifier: "UTC")!; return c }
private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { utc.date(from: DateComponents(year: y, month: m, day: d))! }

@Suite("Goal forecast")
struct GoalForecastTests {
    @Test func projectionMatchesClosedFormEWMA() throws {
        // Constant daily TSS t: ctl_n = t + (ctl0 - t) * (41/42)^n
        let today = day(2026, 11, 17)
        let goal = day(2026, 12, 17)   // 30 days
        let curve = GoalForecast.projection(currentCTL: 30, weeklyTSS: 350, today: today, goal: goal, calendar: utc)
        #expect(curve.count == 31)
        #expect(curve.first?.ctl == 30)
        let expected = 50 + (30 - 50) * pow(41.0 / 42.0, 30)
        let last = try #require(curve.last)
        #expect(abs(last.ctl - expected) < 1e-9)
    }

    @Test func reachesTargetOnFirstDayAtOrAboveIt() throws {
        let today = day(2026, 11, 17)
        let goal = day(2027, 3, 21)
        let f = GoalForecast.forecast(currentCTL: 30, targetCTL: 44, hoursPerWeek: 7, tssPerHour: 60,
                                      today: today, goal: goal, calendar: utc)
        let reach = try #require(f.reachDate)
        #expect(reach < goal)
        let before = utc.date(byAdding: .day, value: -1, to: reach)!
        let curve = GoalForecast.projection(currentCTL: 30, weeklyTSS: 420, today: today, goal: goal, calendar: utc)
        #expect(try #require(curve.first { $0.date == reach }).ctl >= 44)
        #expect(try #require(curve.first { $0.date == before }).ctl < 44)
        #expect(f.text.contains("schon am"))
    }

    @Test func missesTargetWithLowBudget() {
        let f = GoalForecast.forecast(currentCTL: 30, targetCTL: 60, hoursPerWeek: 3, tssPerHour: 50,
                                      today: day(2026, 11, 17), goal: day(2027, 3, 21), calendar: utc)
        #expect(f.reachDate == nil)
        #expect(f.ctlAtGoal < 60)
        #expect(f.text.hasPrefix("Bei 3 h/Woche erreichst du am 21. März Fitness "))
        #expect(f.text.contains("(Ziel 60)"))
    }

    @Test func alreadyAboveTarget() {
        let f = GoalForecast.forecast(currentCTL: 50, targetCTL: 44, hoursPerWeek: 5, tssPerHour: 50,
                                      today: day(2026, 11, 17), goal: day(2027, 3, 21), calendar: utc)
        #expect(f.reachDate == day(2026, 11, 17))
        #expect(f.text.contains("schon erreicht"))
    }

    @Test func hoursFormattingAndFinishedGoal() {
        let f = GoalForecast.forecast(currentCTL: 30, targetCTL: 60, hoursPerWeek: 4.5, tssPerHour: 50,
                                      today: day(2026, 11, 17), goal: day(2027, 3, 21), calendar: utc)
        #expect(f.text.contains("4,5 h/Woche"))
        let done = GoalForecast.forecast(currentCTL: 30, targetCTL: 60, hoursPerWeek: 5, tssPerHour: 50,
                                         today: day(2027, 3, 22), goal: day(2027, 3, 21), calendar: utc)
        #expect(done.ctlAtGoal == 30)
        #expect(done.reachDate == nil)
    }

    @Test func moreHoursMeansMoreFitness() {
        func at(_ h: Double) -> Double {
            GoalForecast.forecast(currentCTL: 30, targetCTL: 60, hoursPerWeek: h, tssPerHour: 50,
                                  today: day(2026, 11, 17), goal: day(2027, 3, 21), calendar: utc).ctlAtGoal
        }
        #expect(at(2) < at(5))
        #expect(at(5) < at(15))
    }

    @Test func tssPerHourFromLastSixWeeksWithFallback() {
        let now = day(2026, 11, 17)
        #expect(GoalForecast.tssPerHour(rides: [], ftp: 250, thresholdHeartRate: nil, now: now) == 50)
        // 1 h at NP 250 / FTP 250 = 100 TSS; 1 h at NP 150 = 36 TSS → 68 TSS/h. A 60-day-old ride is ignored.
        func ride(_ id: Int, daysAgo: Int, np: Double) -> RideSummary {
            RideSummary(id: id, name: "r", sportType: "VirtualRide",
                        startDate: now.addingTimeInterval(-Double(daysAgo) * 86_400), movingTime: 3600, distance: 0,
                        averageWatts: np, weightedAverageWatts: np, trainer: true)
        }
        let rides = [ride(1, daysAgo: 3, np: 250), ride(2, daysAgo: 10, np: 150), ride(3, daysAgo: 60, np: 300)]
        let v = GoalForecast.tssPerHour(rides: rides, ftp: 250, thresholdHeartRate: nil, now: now)
        #expect(abs(v - 68) < 1e-9)
    }
}
