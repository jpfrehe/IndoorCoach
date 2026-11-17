import Foundation
import Testing
@testable import IndoorCoachKit

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return c
}()

private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }

private func series(from start: Date, days: Int, fitness: (Int) -> Double) -> [FitnessFreshness.Point] {
    (0..<days).map { i in
        FitnessFreshness.Point(date: cal.date(byAdding: .day, value: i, to: start)!, load: 0,
                               fitness: fitness(i), fatigue: 0, form: 0)
    }
}

@Suite("Vorjahres-Schatten")
struct SeasonShadowTests {
    @Test func shiftsTheSameWindowOneYearLater() {
        let all = series(from: day(2024, 10, 1), days: 600) { Double($0) / 10 }
        let window = day(2025, 11, 1)...day(2025, 11, 10)
        let shadow = SeasonShadow.points(from: all, window: window, calendar: cal)!
        #expect(shadow.first?.date == day(2025, 11, 1))
        #expect(shadow.last?.date == day(2025, 11, 10))
        #expect(shadow.count == 10)
        // 1 Nov 2024 is day 31 of the series.
        #expect(abs(shadow[0].fitness - 3.1) < 1e-9)
    }

    @Test func nilWithoutPreviousYear() {
        let all = series(from: day(2025, 9, 1), days: 100) { _ in 30 }
        #expect(SeasonShadow.points(from: all, window: day(2025, 11, 1)...day(2025, 11, 10), calendar: cal) == nil)
    }

    @Test func nilWhenPreviousYearIsOnlyWarmupZeros() {
        let all = series(from: day(2024, 10, 1), days: 600) { $0 < 200 ? 0 : 20 }
        #expect(SeasonShadow.points(from: all, window: day(2025, 11, 1)...day(2025, 11, 10), calendar: cal) == nil)
    }

    @Test func leapDayYieldsOnePointPerPlottedDay() {
        let all = series(from: day(2024, 1, 1), days: 800) { _ in 25 }
        let shadow = SeasonShadow.points(from: all, window: day(2025, 2, 25)...day(2025, 3, 3), calendar: cal)!
        #expect(Set(shadow.map(\.date)).count == shadow.count)
    }

    @Test func partialPreviousYearKeepsWhatExists() {
        let all = series(from: day(2024, 11, 5), days: 400) { _ in 20 }
        let shadow = SeasonShadow.points(from: all, window: day(2025, 11, 1)...day(2025, 11, 10), calendar: cal)!
        #expect(shadow.first?.date == day(2025, 11, 5))
    }

    @Test func fitnessOnDayAndText() {
        let shadow = [SeasonShadow.Point(date: day(2025, 11, 16), fitness: 29), .init(date: day(2025, 11, 17), fitness: 29.4)]
        #expect(SeasonShadow.fitness(on: day(2025, 11, 17), in: shadow, calendar: cal) == 29.4)
        #expect(SeasonShadow.fitness(on: day(2025, 11, 20), in: shadow, calendar: cal) == nil)
        #expect(SeasonShadow.comparisonText(today: 34, previous: 29) == "Heute 34, Vorjahr 29")
        #expect(SeasonShadow.comparisonText(today: 34, previous: nil) == "Heute 34")
    }
}
