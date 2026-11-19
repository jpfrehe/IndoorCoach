import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("Erholungs-Trend (Basis, MAD, Mittel)")
struct WellnessTrendTests {
    static var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let watch = HealthSourceRef(name: "Apple Watch", bundleID: "com.apple.health.watch")
    static let garmin = HealthSourceRef(name: "Garmin Connect", bundleID: "com.garmin.connect")

    /// Ein Wert pro Tag, `values[0]` = ältester Tag, letzter Wert = heute.
    static func series(_ values: [Double], metric: HealthMetric = .restingHR, source: HealthSourceRef = watch) -> [HealthDaily] {
        let today = cal.startOfDay(for: now)
        return values.enumerated().map { i, v in
            HealthDaily(date: cal.date(byAdding: .day, value: i - (values.count - 1), to: today)!, metric: metric, value: v, source: source)
        }
    }

    static func trend(_ values: [Double], metric: HealthMetric = .restingHR) -> WellnessTrend {
        WellnessTrend.make(metric: metric, dailies: series(values, metric: metric), asOf: now, calendar: cal)
    }

    @Test func medianAndMAD() {
        #expect(Wellness.median([3, 1, 2]) == 2)
        #expect(Wellness.median([1, 2, 3, 4]) == 2.5)
        #expect(Wellness.median([]) == nil)
        // Median 3, Abweichungen 2,1,0,1,2 -> MAD 1
        #expect(Wellness.mad([1, 2, 3, 4, 5]) == 1)
        #expect(Wellness.mad([]) == nil)
    }

    @Test func showsFromTwentyOneDays() {
        #expect(!Self.trend(Array(repeating: 50, count: 20)).isReady)
        #expect(Self.trend(Array(repeating: 50, count: 20)).baseline == nil)
        let ready = Self.trend(Array(repeating: 50, count: 21))
        #expect(ready.isReady)
        #expect(ready.baseline == 50)
        #expect(ready.dayCount == 21)
    }

    @Test func gapsCountAsMissingDays() {
        // 21 Werte verteilt über 28 Tage (jeder 4. Tag fehlt) -> 21 Tage mit Werten
        var days = Self.series(Array(repeating: 50, count: 28))
        days = days.enumerated().filter { $0.offset % 4 != 0 }.map(\.element)
        #expect(days.count == 21)
        #expect(WellnessTrend.make(metric: .restingHR, dailies: days, asOf: Self.now, calendar: Self.cal).isReady)
        #expect(!WellnessTrend.make(metric: .restingHR, dailies: Array(days.dropFirst()), asOf: Self.now, calendar: Self.cal).isReady)
    }

    @Test func baselineWindowIsTwentyEightDays() {
        // 40 Tage: die ältesten 12 (Wert 100) liegen außerhalb des Fensters
        let values = Array(repeating: 100.0, count: 12) + Array(repeating: 50.0, count: 28)
        let t = Self.trend(values)
        #expect(t.baseline == 50)
        #expect(t.dayCount == 28)
    }

    @Test func baselineIsMedianNotMean() {
        let values = Array(repeating: 50.0, count: 25) + [90, 90, 90]
        #expect(Self.trend(values).baseline == 50)
    }

    @Test func threeAndSevenDayMeans() {
        let values = Array(repeating: 50.0, count: 21) + [50, 50, 50, 50, 56, 56, 59]
        let t = Self.trend(values)
        #expect(t.mean3 == (56 + 56 + 59) / 3.0)
        #expect(t.mean7 == (50 + 50 + 56 + 56 + 59 + 50 + 50) / 7.0)
    }

    @Test func meansNeedEnoughDaysInTheirWindow() {
        // Heute und gestern fehlen: im 3-Tage-Fenster bleibt 1 Wert (< 2) -> nil, im 7-Tage-Fenster 5 (>= 4)
        let days = Array(Self.series(Array(repeating: 50, count: 28)).dropLast(2))
        let t = WellnessTrend.make(metric: .restingHR, dailies: days, asOf: Self.now, calendar: Self.cal)
        #expect(t.mean3 == nil)
        #expect(t.mean7 == 50)
    }

    @Test func sourceChangeStartsNewBaseline() {
        let old = Self.series(Array(repeating: 70, count: 40), source: Self.garmin).dropLast(10)
        let new = Self.series(Array(repeating: 50, count: 10), source: Self.watch)
        let t = WellnessTrend.make(metric: .restingHR, dailies: Array(old) + new, asOf: Self.now, calendar: Self.cal)
        #expect(t.source == Self.watch)
        #expect(t.dayCount == 10)
        #expect(!t.isReady)
        #expect(t.baseline == nil)
    }

    @Test func otherMetricsAreIgnored() {
        let mixed = Self.series(Array(repeating: 50, count: 28)) + Self.series(Array(repeating: 9, count: 28), metric: .sleepHours)
        let t = WellnessTrend.make(metric: .restingHR, dailies: mixed, asOf: Self.now, calendar: Self.cal)
        #expect(t.baseline == 50)
    }

    @Test func madIsRawMedianAbsoluteDeviation() {
        let values = (0..<28).map { 50.0 + Double($0 % 5) - 2 } // 48...52
        let t = Self.trend(values)
        #expect(t.mad != nil)
        #expect(t.mad! >= 1 && t.mad! <= 2)
    }

    @Test func hrvUsesNaturalLog() {
        let t = Self.trend(Array(repeating: 40.0, count: 28), metric: .hrvSDNN)
        #expect(abs(t.lnBaseline! - log(40.0)) < 1e-9)
        #expect(abs(t.lnSD!) < 1e-9)
        #expect(abs(t.lnMean7! - log(40.0)) < 1e-9)
    }

    @Test func emptyInputIsNotReady() {
        let t = WellnessTrend.make(metric: .restingHR, dailies: [], asOf: Self.now, calendar: Self.cal)
        #expect(!t.isReady && t.source == nil && t.dayCount == 0 && t.mean3 == nil)
    }
}
