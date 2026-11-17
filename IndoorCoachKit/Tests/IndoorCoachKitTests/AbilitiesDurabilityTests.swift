import Foundation
import Testing
@testable import IndoorCoachKit

private let day: TimeInterval = 86_400
private let now = Date(timeIntervalSince1970: 1_794_000_000)

private func ride(_ id: Int, daysAgo: Double, curve: [Int: Double]? = nil, avg: Double? = nil, minutes: Int = 90) -> RideSummary {
    var r = RideSummary(id: id, name: "R\(id)", sportType: "VirtualRide", startDate: now.addingTimeInterval(-daysAgo * day),
                        movingTime: minutes * 60, distance: 1, averageWatts: avg, trainer: true)
    r.powerCurve = curve
    return r
}

@Suite("AbilityLevels")
struct AbilityLevelsTests {
    private let threshold = AbilityLevels.bands[1]

    @Test func bandEdgesAndClamping() {
        #expect(AbilityLevels.level(wattsPerKg: 2.0, band: threshold) == 1)
        #expect(AbilityLevels.level(wattsPerKg: 5.0, band: threshold) == 10)
        #expect(AbilityLevels.level(wattsPerKg: 1.0, band: threshold) == 1)
        #expect(AbilityLevels.level(wattsPerKg: 7.0, band: threshold) == 10)
        #expect(AbilityLevels.level(wattsPerKg: 3.5, band: threshold) == 6)      // 1 + 9 * 0.5 = 5.5 → 6
    }

    @Test func documentedBands() {
        let b = AbilityLevels.bands
        #expect(b.map(\.duration) == [3600, 1200, 300, 60])
        #expect(b[0].lowWkg == 1.8 && b[0].highWkg == 4.6)
        #expect(b[2].lowWkg == 2.5 && b[2].highWkg == 6.4)
        #expect(b[3].lowWkg == 4.0 && b[3].highWkg == 9.0)
    }

    @Test func levelsFromMeasuredCurve() {
        let r = ride(1, daysAgo: 5, curve: [60: 450, 300: 320, 1200: 250, 3600: 200])
        let a = AbilityLevels.abilities(rides: [r], weightKg: 75, now: now)
        #expect(a.count == 4)
        #expect(a[1].level == AbilityLevels.level(wattsPerKg: 250.0 / 75, band: threshold))
        #expect(a.allSatisfy { $0.level != nil && !$0.isFloor && $0.change == nil })
    }

    @Test func floorPointsAreMarked() {
        let a = AbilityLevels.abilities(rides: [ride(1, daysAgo: 5, avg: 200)], weightKg: 70, now: now)
        #expect(a[0].isFloor && a[0].level != nil)       // 60 min lower bound from the average
        #expect(a[0].watts == 200)
    }

    @Test func changeAgainstPreviousQuarter() {
        let old = ride(1, daysAgo: 120, curve: [1200: 200])
        let new = ride(2, daysAgo: 10, curve: [1200: 300])
        let a = AbilityLevels.abilities(rides: [old, new], weightKg: 75, now: now)
        let expected = AbilityLevels.level(wattsPerKg: 4.0, band: threshold) - AbilityLevels.level(wattsPerKg: 200.0 / 75, band: threshold)
        #expect(a[1].change == expected && expected > 0)
        #expect(a[0].level == nil)                        // no 60-min value at all
    }

    @Test func oldRidesAndMissingWeightGiveNoLevel() {
        let old = ride(1, daysAgo: 100, curve: [1200: 300])
        #expect(AbilityLevels.abilities(rides: [old], weightKg: 75, now: now)[1].level == nil)
        #expect(AbilityLevels.abilities(rides: [ride(2, daysAgo: 3, curve: [1200: 300])], weightKg: 0, now: now)[1].level == nil)
    }
}

@Suite("Durability")
struct DurabilityTests {
    @Test func lateHourAgainstOverallBest() throws {
        // 300 W for 10 min at the start, then 240 W: last hour (of 70 min) only sees 240 W.
        let series = Array(repeating: 300.0, count: 600) + Array(repeating: 240.0, count: 3600)
        let p = try #require(Durability.percent(power: series))
        #expect(abs(p - 80) < 1e-9)
    }

    @Test func constantPowerIs100AndBestLateIs100() {
        #expect(Durability.percent(power: Array(repeating: 200, count: 3700)) == 100)
        let late = Array(repeating: 150.0, count: 3600) + Array(repeating: 280.0, count: 300)
        #expect(Durability.percent(power: late) == 100)
    }

    @Test func shortOrPowerlessSeriesGiveNil() {
        #expect(Durability.percent(power: Array(repeating: 200, count: 3599)) == nil)
        #expect(Durability.percent(power: Array(repeating: 0, count: 4000)) == nil)
    }

    @Test func averageOverNinetyDays() throws {
        var a = ride(1, daysAgo: 3); a.durability = 90
        var b = ride(2, daysAgo: 20); b.durability = 80
        var old = ride(3, daysAgo: 200); old.durability = 50
        let none = ride(4, daysAgo: 2)
        let avg = try #require(Durability.average(rides: [a, b, old, none], now: now))
        #expect(avg.percent == 85 && avg.count == 2)
        #expect(Durability.average(rides: [none], now: now) == nil)
    }

    @Test func ratings() {
        #expect(Durability.rating(percent: 90) == .high)
        #expect(Durability.rating(percent: 85) == .medium)
        #expect(Durability.rating(percent: 79.9) == .low)
    }

    @Test func fitImportComputesDurabilityAndStoredRideKeepsIt() throws {
        var fit = FITBuilder()
        let t0 = fitTime(rideStart)
        func w(_ s: Int) -> UInt64 { s < 600 ? 300 : 240 }
        fit.message(global: 20, fields: [(253, 4, t0), (7, 2, w(0))])
        for s in 1..<4200 { fit.data([(4, t0 + UInt64(s)), (2, w(s))]) }
        let summary = try FITParser.summary(from: fit.bytes)
        let d = try #require(summary.durability)
        #expect(abs(d - 80) < 1e-6)
        var ride = RideSummary(fit: summary, id: -5, name: "x")
        #expect(ride.durability == summary.durability)
        let stored = StoredRide(ride)
        #expect(stored.summary.durability == ride.durability)
        ride.durability = nil
        ride.name = "synced"
        stored.update(from: ride)
        #expect(stored.name == "synced" && stored.durability != nil)   // summary-only sync keeps it
    }
}
