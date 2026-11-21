import Foundation
import Testing
@testable import IndoorCoachKit

private var utc: Calendar { var c = Calendar(identifier: .iso8601); c.timeZone = TimeZone(identifier: "UTC")!; return c }
private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { utc.date(from: DateComponents(year: y, month: m, day: d))! }

@Suite("Diagramme P2 (AP6)")
struct ChartP2Tests {
    @Test func forecastCrossingDateMatchesSentence() throws {
        let f = GoalForecast.forecast(currentCTL: 30, targetCTL: 44, hoursPerWeek: 7, tssPerHour: 60,
                                      today: day(2026, 11, 17), goal: day(2027, 3, 21), calendar: utc)
        let crossing = try #require(f.crossing)
        #expect(crossing.date == f.reachDate)
        #expect(crossing.ctl >= 44)
        #expect(f.text.contains(GoalForecast.dayText(crossing.date, calendar: utc)))
        // "22. Januar" and "22. Jan." start with the same day number.
        let dayNumber = GoalForecast.dayText(crossing.date, calendar: utc).prefix { $0 != " " }
        #expect(GoalForecast.crossingLabel(crossing.date, calendar: utc).hasPrefix(dayNumber))
    }

    @Test func forecastHasNoCrossingWhenAlreadyReachedOrMissed() {
        let reached = GoalForecast.forecast(currentCTL: 50, targetCTL: 44, hoursPerWeek: 7, tssPerHour: 60,
                                            today: day(2026, 11, 17), goal: day(2027, 3, 21), calendar: utc)
        #expect(reached.crossing == nil)
        let missed = GoalForecast.forecast(currentCTL: 30, targetCTL: 60, hoursPerWeek: 3, tssPerHour: 50,
                                           today: day(2026, 11, 17), goal: day(2027, 3, 21), calendar: utc)
        #expect(missed.crossing == nil)
    }

    @Test func distributionLabelFitsOrHides() {
        #expect(TrainingDistribution.segmentLabel(percent: 46, barWidth: 300, textWidth: 28) == "46 %")
        #expect(TrainingDistribution.segmentLabel(percent: 0, barWidth: 300, textWidth: 28) == nil)
        // 5 % of 300 pt = 15 pt: too narrow for text plus padding.
        #expect(TrainingDistribution.segmentLabel(percent: 5, barWidth: 300, textWidth: 28) == nil)
        #expect(TrainingDistribution.segmentLabel(percent: 14, barWidth: 300, textWidth: 28) == "14 %")
        #expect(TrainingDistribution.segmentLabel(percent: 46, barWidth: 0, textWidth: 28) == nil)
    }
}
