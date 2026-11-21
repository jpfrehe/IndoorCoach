import Foundation
import Testing
@testable import IndoorCoachKit

/// Data preparation for the P1 analysis charts (concept 21 §5, AP5).
@Suite("ChartSeries")
struct ChartSeriesTests {
    @Test func formBarColorFollowsSign() {
        #expect(ChartSeries.formSide(12) == .recovered)
        #expect(ChartSeries.formSide(0.1) == .recovered)
        #expect(ChartSeries.formSide(0) == .loaded)
        #expect(ChartSeries.formSide(-35) == .loaded)
    }

    @Test func weekBarsHighlightOnlyCurrent() {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_763_800_000)
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: now)!.start
        let starts = (0..<12).map { cal.date(byAdding: .weekOfYear, value: $0 - 11, to: thisWeek)! }
        let flags = ChartSeries.currentWeekFlags(weekStarts: starts, now: now, calendar: cal)
        #expect(flags.count == 12)
        #expect(flags.filter { $0 }.count == 1)
        #expect(flags.last == true)
    }

    @Test func complianceIstIsSmoothedAndBounded() {
        var watts = (0..<7200).map { 200 + Double($0 % 7) }
        watts[3000] = 900
        let ist = ChartSeries.smoothedActual(watts)
        #expect(ist.count <= ChartSeries.maxActualPoints)
        #expect(ist.first?.minute == 0)
        // 30-s mean: the spike is averaged, never the raw 900 W.
        #expect((ist.map(\.watts).max() ?? 0) < 300)
        #expect(zip(ist, ist.dropFirst()).allSatisfy { $0.minute < $1.minute })
    }

    @Test func targetKeepsStepEdgesExact() {
        let target = [Double](repeating: 100, count: 600) + [Double](repeating: 250, count: 300) + [Double](repeating: 100, count: 600)
        let soll = ChartSeries.targetSteps(target)
        #expect(soll.count <= 8)
        #expect(ChartSeries.value(soll, atMinute: 9.9) == 100)
        #expect(ChartSeries.value(soll, atMinute: 10.0) == 250)
        #expect(ChartSeries.value(soll, atMinute: 14.9) == 250)
        #expect(ChartSeries.value(soll, atMinute: 15.0) == 100)
    }

    @Test func targetRampIsBounded() {
        let ramp = (0..<3600).map { 100 + Double($0) / 10 }
        #expect(ChartSeries.targetSteps(ramp).count <= ChartSeries.maxActualPoints)
        #expect(ChartSeries.targetSteps([]).isEmpty)
    }
}
