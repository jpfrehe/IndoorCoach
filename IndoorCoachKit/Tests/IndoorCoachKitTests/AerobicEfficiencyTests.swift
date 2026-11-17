import Foundation
import Testing
@testable import IndoorCoachKit

private let now = Date(timeIntervalSince1970: 1_794_000_000)   // Nov 2026
private var cal: Calendar { var c = Calendar(identifier: .iso8601); c.timeZone = TimeZone(identifier: "UTC")!; return c }

private func ride(daysAgo: Double, minutes: Int = 60, avg: Double? = 150, np: Double? = 160, hr: Double? = 130, id: Int = 0) -> RideSummary {
    RideSummary(id: id == 0 ? Int(daysAgo * 100) + 1 : id, name: "r", sportType: "VirtualRide",
                startDate: now.addingTimeInterval(-daysAgo * 86_400), movingTime: minutes * 60, distance: 30_000,
                averageWatts: avg, weightedAverageWatts: np, averageHeartrate: hr, trainer: true)
}

@Suite("Aerobic efficiency")
struct AerobicEfficiencyTests {
    @Test func factorIsNPOverHeartRate() throws {
        let ef = try #require(AerobicEfficiency.factor(for: ride(daysAgo: 1, np: 160, hr: 128), ftp: 250))
        #expect(abs(ef - 1.25) < 1e-9)
    }

    @Test func factorFallsBackToAverageWatts() throws {
        let ef = try #require(AerobicEfficiency.factor(for: ride(daysAgo: 1, avg: 150, np: nil, hr: 150), ftp: 250))
        #expect(abs(ef - 1.0) < 1e-9)
    }

    @Test func factorFilters() {
        #expect(AerobicEfficiency.factor(for: ride(daysAgo: 1, hr: nil), ftp: 250) == nil)
        #expect(AerobicEfficiency.factor(for: ride(daysAgo: 1, hr: 0), ftp: 250) == nil)
        #expect(AerobicEfficiency.factor(for: ride(daysAgo: 1, avg: nil, np: nil), ftp: 250) == nil)
        #expect(AerobicEfficiency.factor(for: ride(daysAgo: 1, minutes: 19), ftp: 250) == nil)
        #expect(AerobicEfficiency.factor(for: ride(daysAgo: 1, minutes: 20), ftp: 250) != nil)
        // IF 0.85 still counts (212.5 / 250), above does not.
        #expect(AerobicEfficiency.factor(for: ride(daysAgo: 1, np: 212.5), ftp: 250) != nil)
        #expect(AerobicEfficiency.factor(for: ride(daysAgo: 1, np: 215), ftp: 250) == nil)
        // Without NP the IF comes from average × 1.05: 205 W → 215.25 W → 0.861.
        #expect(AerobicEfficiency.factor(for: ride(daysAgo: 1, avg: 205, np: nil), ftp: 250) == nil)
        #expect(AerobicEfficiency.factor(for: ride(daysAgo: 1, avg: 200, np: nil), ftp: 250) != nil)
    }

    @Test func medianOddEvenEmpty() {
        #expect(AerobicEfficiency.median([3, 1, 2]) == 2)
        #expect(AerobicEfficiency.median([4, 1, 2, 3]) == 2.5)
        #expect(AerobicEfficiency.median([]) == nil)
    }

    @Test func weeklySeriesUsesMedianPerWeekAndSkipsEmptyWeeks() {
        // Three rides in one week (EF 1.0, 1.2, 2.0 → median 1.2), one two weeks earlier, one non-qualifying.
        let week = [ride(daysAgo: 1, np: 130, hr: 130, id: 1), ride(daysAgo: 1.1, np: 156, hr: 130, id: 2), ride(daysAgo: 1.2, np: 200, hr: 100, id: 3)]
        let older = ride(daysAgo: 15, np: 130, hr: 130, id: 4)
        let skipped = ride(daysAgo: 8, hr: nil, id: 5)
        let series = AerobicEfficiency.weeklySeries(rides: week + [older, skipped], ftp: 250,
                                                    from: now.addingTimeInterval(-30 * 86_400), to: now, calendar: cal)
        #expect(series.count == 2)
        #expect(series[0].rides == 1 && abs(series[0].ef - 1.0) < 1e-9)
        #expect(series[1].rides == 3 && abs(series[1].ef - 1.2) < 1e-9)
        #expect(series[0].weekStart < series[1].weekStart)
    }

    private func trendRides(recentHR: Double, previousHR: Double) -> [RideSummary] {
        (0..<3).map { ride(daysAgo: Double($0) * 5 + 1, np: 150, hr: recentHR, id: 100 + $0) }
            + (0..<3).map { ride(daysAgo: 43 + Double($0) * 5, np: 150, hr: previousHR, id: 200 + $0) }
    }

    @Test func trendImprovingWithGermanText() throws {
        // Same power, pulse 125 instead of 130 → EF +4 %.
        let t = try #require(AerobicEfficiency.trend(rides: trendRides(recentHR: 125, previousHR: 130), ftp: 250, now: now))
        #expect(t.direction == .improving)
        #expect(abs(t.changePercent - 4.0) < 1e-9)
        #expect(t.text == "+4 %: gleiche Leistung mit weniger Puls")
    }

    @Test func trendDeclining() throws {
        let t = try #require(AerobicEfficiency.trend(rides: trendRides(recentHR: 135, previousHR: 130), ftp: 250, now: now))
        #expect(t.direction == .declining)
        #expect(t.changePercent < -2)
        #expect(t.text.hasPrefix("−4 %") && t.text.contains("mehr Puls"))
    }

    @Test func trendThresholdsAtPlusMinusTwoPercent() throws {
        // Recent EF vs previous EF (HR 130): 127.4 → +2.04 % improving; 128 → +1.6 % stable.
        let up = try #require(AerobicEfficiency.trend(rides: trendRides(recentHR: 127.4, previousHR: 130), ftp: 250, now: now))
        #expect(up.direction == .improving)
        let flat = try #require(AerobicEfficiency.trend(rides: trendRides(recentHR: 128, previousHR: 130), ftp: 250, now: now))
        #expect(flat.direction == .stable)
        #expect(flat.text.hasPrefix("Stabil"))
        let down = try #require(AerobicEfficiency.trend(rides: trendRides(recentHR: 132.7, previousHR: 130), ftp: 250, now: now))
        #expect(down.direction == .declining)
        let almost = try #require(AerobicEfficiency.trend(rides: trendRides(recentHR: 131.5, previousHR: 130), ftp: 250, now: now))
        #expect(almost.direction == .stable)
    }

    @Test func trendNeedsTwoRidesInBothWindows() {
        let onlyRecent = (0..<4).map { ride(daysAgo: Double($0) + 1, id: 300 + $0) }
        #expect(AerobicEfficiency.trend(rides: onlyRecent, ftp: 250, now: now) == nil)
        let thin = [ride(daysAgo: 1, id: 1), ride(daysAgo: 2, id: 2), ride(daysAgo: 50, id: 3)]
        #expect(AerobicEfficiency.trend(rides: thin, ftp: 250, now: now) == nil)
    }

    @Test func coverageCountsRidesWithPowerAndHeartRate() {
        let rides = [ride(daysAgo: 1, id: 1), ride(daysAgo: 2, hr: nil, id: 2), ride(daysAgo: 3, avg: nil, np: nil, id: 3),
                     ride(daysAgo: 4, minutes: 10, id: 4), ride(daysAgo: 400, id: 5)]
        let c = AerobicEfficiency.coverage(rides: rides, ftp: 250, from: now.addingTimeInterval(-90 * 86_400), to: now)
        #expect(c.total == 4)
        #expect(c.withData == 2)        // rides 1 and 4
        #expect(c.comparable == 1)      // ride 4 is under 20 min
        #expect(c.isLow)
        #expect(AerobicEfficiency.coverage(rides: [], ftp: 250, from: now, to: now).isLow)
    }

    @Test func coverageNotLowWithEnoughComparableRides() {
        let rides = (1...5).map { ride(daysAgo: Double($0), id: $0) }
        #expect(!AerobicEfficiency.coverage(rides: rides, ftp: 250, from: now.addingTimeInterval(-86_400 * 30), to: now).isLow)
    }

    // MARK: Decoupling

    @Test func decouplingZeroForConstantSeries() throws {
        let d = try #require(AerobicEfficiency.decoupling(power: Array(repeating: 200, count: 3600), heartRate: Array(repeating: 140, count: 3600)))
        #expect(abs(d) < 1e-9)
    }

    @Test func decouplingPositiveWhenHeartRateDrifts() throws {
        // First half 200 W / 140 bpm, second half 200 W / 147 bpm → 4.76 %.
        let hr = Array(repeating: 140.0, count: 1800) + Array(repeating: 147.0, count: 1800)
        let d = try #require(AerobicEfficiency.decoupling(power: Array(repeating: 200, count: 3600), heartRate: hr))
        #expect(abs(d - (1 - 140.0 / 147.0) * 100) < 1e-9)
        #expect(AerobicEfficiency.rating(decoupling: d) == .stable)
    }

    @Test func decouplingNegativeWhenPulseFalls() throws {
        let hr = Array(repeating: 150.0, count: 1800) + Array(repeating: 140.0, count: 1800)
        let d = try #require(AerobicEfficiency.decoupling(power: Array(repeating: 200, count: 3600), heartRate: hr))
        #expect(d < 0)
    }

    @Test func decouplingIgnoresSecondsWithoutHeartRate() throws {
        var hr = Array(repeating: 140.0, count: 3600)
        for i in 100..<300 { hr[i] = 0 }                                // dropout in the first half, still > 50 % valid
        let d = try #require(AerobicEfficiency.decoupling(power: Array(repeating: 200, count: 3600), heartRate: hr))
        #expect(abs(d) < 1e-9)
    }

    @Test func decouplingNeedsLengthAndHeartRateCoverage() {
        #expect(AerobicEfficiency.decoupling(power: Array(repeating: 200, count: 1199), heartRate: Array(repeating: 140, count: 1199)) == nil)
        #expect(AerobicEfficiency.decoupling(power: Array(repeating: 200, count: 1200), heartRate: Array(repeating: 140, count: 1200)) != nil)
        #expect(AerobicEfficiency.decoupling(power: Array(repeating: 200, count: 3600), heartRate: Array(repeating: 0, count: 3600)) == nil)
        let sparse = Array(repeating: 140.0, count: 800) + Array(repeating: 0.0, count: 1000) + Array(repeating: 140.0, count: 1800)
        #expect(AerobicEfficiency.decoupling(power: Array(repeating: 200, count: 3600), heartRate: sparse) == nil)
    }

    @Test func ratings() {
        #expect(AerobicEfficiency.rating(decoupling: 4.9) == .stable)
        #expect(AerobicEfficiency.rating(decoupling: -3) == .stable)
        #expect(AerobicEfficiency.rating(decoupling: 5) == .slight)
        #expect(AerobicEfficiency.rating(decoupling: 12) == .strong)
        #expect(AerobicEfficiency.rating(decoupling: 4.9).label == "stabil")
    }
}
