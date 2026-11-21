import Foundation
import Testing
@testable import IndoorCoachKit

/// Pure chart helpers (concept 21 §6, AP4).
@Suite("ChartMath")
struct ChartMathTests {
    // MARK: Ticks and domains

    @Test func niceTicksRoundValues() {
        #expect(ChartMath.niceTicks(min: 37, max: 262, count: 4) == [0, 100, 200, 300])
        let eff = ChartMath.niceTicks(min: 1.41, max: 1.58, count: 3)
        #expect(eff.count == 3)
        for (a, b) in zip(eff, [1.4, 1.5, 1.6]) { #expect(abs(a - b) < 1e-9) }
    }

    @Test func niceTicksNeverEmpty() {
        #expect(!ChartMath.niceTicks(min: 5, max: 5, count: 3).isEmpty)
        #expect(!ChartMath.niceTicks(min: 0, max: 0, count: 4).isEmpty)
        #expect(!ChartMath.niceTicks(min: 9, max: 1, count: 4).isEmpty)   // swapped
        #expect(!ChartMath.niceTicks(min: 1, max: 2, count: 0).isEmpty)
        let ticks = ChartMath.niceTicks(min: 0, max: 1e9, count: 4)
        #expect(ticks.count >= 2 && ticks.count <= 8)
    }

    @Test func domainNeverCollapses() {
        let d = ChartMath.domain(values: [7, 7, 7], includeZero: false)
        #expect(d == 6...8)
        let empty = ChartMath.domain(values: [], includeZero: false)
        #expect(empty.lowerBound < empty.upperBound)
        let zero = ChartMath.domain(values: [0, 0], includeZero: true)
        #expect(zero.lowerBound < zero.upperBound)
    }

    @Test func domainExcludesZeroWhenAsked() {
        let d = ChartMath.domain(values: [38, 44, 52], includeZero: false)
        #expect(d.lowerBound > 0 && d.lowerBound <= 38 && d.upperBound >= 52)
        let z = ChartMath.domain(values: [38, 44, 52], includeZero: true)
        #expect(z.lowerBound == 0 && z.upperBound >= 52)
    }

    @Test func minuteTicksAreRound() {
        #expect(ChartMath.minuteTicks(total: 60 * 60) == [0, 15, 30, 45, 60])
        #expect(ChartMath.minuteTicks(total: 45 * 60) == [0, 15, 30, 45])
        #expect(ChartMath.minuteTicks(total: 95 * 60) == [0, 30, 60, 90])
        #expect(ChartMath.minuteTicks(total: 0) == [0])
    }

    @Test func powerCurveTicksDropCrowdedSixtyMinutes() {
        #expect(ChartMath.powerCurveTicks(maxDuration: 30 * 60) == [5, 60, 300, 1200])
        #expect(ChartMath.powerCurveTicks(maxDuration: 60 * 60) == [5, 60, 300, 1200, 3600])
        #expect(ChartMath.powerCurveTicks(maxDuration: 44 * 60) == [5, 60, 300, 1200])
        #expect(ChartMath.powerCurveTicks(maxDuration: 3) == [5])
    }

    // MARK: Smoothing and thinning

    @Test func rollingMeanKeepsConstantAndLength() {
        let out = ChartMath.rollingMean(Array(repeating: 200, count: 50), window: 3)
        #expect(out.count == 50)
        #expect(out.allSatisfy { abs($0 - 200) < 1e-9 })
        #expect(ChartMath.rollingMean([], window: 3).isEmpty)
    }

    @Test func rollingMeanStepIsMonotone() {
        let step = Array(repeating: 100.0, count: 10) + Array(repeating: 300.0, count: 10)
        let out = ChartMath.rollingMean(step, window: 5)
        #expect(zip(out, out.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(out.min()! >= 100 && out.max()! <= 300)
        #expect(out.last == 300)
    }

    @Test func rollingMeanIgnoresDropouts() {
        let out = ChartMath.rollingMean([200, 0, 200, 0, 200], window: 5)
        #expect(abs(out.last! - 200) < 1e-9)
        #expect(ChartMath.rollingMean([0, 0, 0], window: 3) == [0, 0, 0])
    }

    @Test func downsampleKeepsExtremesAndBound() {
        var values = (0..<5_000).map { 200 + 20 * sin(Double($0) / 40) }
        values[1234] = 900; values[3333] = -50
        let idx = ChartMath.downsampleMinMax(values, maxPoints: 400)
        #expect(idx.count <= 400)
        #expect(idx.first == 0 && idx.last == 4_999)
        #expect(idx.contains(1234) && idx.contains(3333))
        #expect(idx == idx.sorted() && Set(idx).count == idx.count)
        #expect(ChartMath.downsampleMinMax([1, 2, 3], maxPoints: 400) == [0, 1, 2])
    }

    // MARK: Gaps and selection

    @Test func segmentsSplitOnGaps() {
        let day: TimeInterval = 86_400
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let dates = [0, 1, 2, 12, 13, 30].map { t0.addingTimeInterval(Double($0) * day) }
        let segs = ChartMath.segments(dates, splitWhenGapExceeds: 7 * day)
        #expect(segs == [0..<3, 3..<5, 5..<6])
        #expect(ChartMath.segments([], splitWhenGapExceeds: day).isEmpty)
        #expect(ChartMath.segments(dates, splitWhenGapExceeds: 100 * day) == [0..<6])
    }

    @Test func nearestPicksClosestDate() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let dates = [0, 10, 20].map { t0.addingTimeInterval(Double($0) * 86_400) }
        #expect(ChartMath.nearest(dates, to: t0.addingTimeInterval(8 * 86_400)) == 1)
        #expect(ChartMath.nearest(dates, to: t0.addingTimeInterval(-99 * 86_400)) == 0)
        #expect(ChartMath.nearest([Date](), to: t0) == nil)
        #expect(ChartMath.nearest([5.0, 60, 300], to: 100.0) == 1)
    }

    // MARK: Words

    @Test func accessibilitySentenceForSeries() {
        let s = ChartMath.seriesSentence(name: "Fitness", values: [35, 40, 31, 38], decimals: 0, period: "7 Tagen")
        #expect(s.contains("Fitness 38"))
        #expect(s.contains("plus 3 in 7 Tagen"))
        #expect(s.contains("Höchstwert 40") && s.contains("Tiefstwert 31"))
        let d = ChartMath.seriesSentence(name: "Effizienz", values: [1.5, 1.52], decimals: 2, unit: " W/bpm")
        #expect(d.contains("1,52 W/bpm"))
        #expect(d.contains("plus 0,02"))
        let down = ChartMath.seriesSentence(name: "Ruhepuls", values: [60, 55], period: nil)
        #expect(down.contains("minus 5"))
        #expect(ChartMath.seriesSentence(name: "X", values: []) == "X: keine Daten.")
        #expect(ChartMath.seriesSentence(name: "X", values: [4]).contains("X 4"))
    }
}
