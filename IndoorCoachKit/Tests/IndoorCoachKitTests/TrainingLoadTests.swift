import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("Training load")
struct TrainingLoadTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 18) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    func ride(_ id: Int, _ date: Date, minutes: Int, np: Double? = nil, avg: Double? = nil, hr: Double? = nil,
              sport: String = "VirtualRide", trainer: Bool = true) -> RideSummary {
        RideSummary(id: id, name: "Ride \(id)", sportType: sport, startDate: date, movingTime: minutes * 60,
                    distance: Double(minutes) * 500, averageWatts: avg, weightedAverageWatts: np,
                    kilojoules: avg.map { $0 * Double(minutes) * 60 / 1000 }, averageHeartrate: hr, trainer: trainer)
    }

    @Test func tssFromWeightedPower() {
        let r = ride(1, day(2026, 11, 2), minutes: 60, np: 250)
        let est = TrainingLoad.estimateTSS(for: r, ftp: 250)
        #expect(est.source == .power)
        #expect(abs(est.tss - 100) < 0.001)
    }

    @Test func tssFallsBackToAveragePowerWithVariabilityBump() {
        let r = ride(1, day(2026, 11, 2), minutes: 60, avg: 200)
        let est = TrainingLoad.estimateTSS(for: r, ftp: 250)
        // 200 × 1.05 = 210 → IF 0.84 → 70.56 TSS
        #expect(abs(est.tss - 70.56) < 0.01)
    }

    @Test func tssFromHeartRateWhenNoPower() {
        let r = ride(1, day(2026, 11, 2), minutes: 120, hr: 135)
        let est = TrainingLoad.estimateTSS(for: r, ftp: 250, thresholdHeartRate: 170)
        #expect(est.source == .heartRate)
        #expect(abs(est.tss - 2 * pow(135.0 / 170.0, 2) * 100) < 0.001)
    }

    @Test func tssFallsBackToDuration() {
        let r = ride(1, day(2026, 11, 2), minutes: 90)
        let est = TrainingLoad.estimateTSS(for: r, ftp: 250)
        #expect(est.source == .duration)
        #expect(est.tss == 75)
    }

    @Test func ctlAndAtlMoveTowardsConstantLoad() {
        let start = day(2026, 1, 1, hour: 0)
        var daily: [Date: Double] = [:]
        for i in 0..<200 {
            daily[calendar.startOfDay(for: calendar.date(byAdding: .day, value: i, to: start)!)] = 60
        }
        let series = TrainingLoad.series(dailyTSS: daily, from: start,
                                         to: calendar.date(byAdding: .day, value: 199, to: start)!, calendar: calendar)
        #expect(series.count == 200)
        #expect(abs(series.last!.ctl - 60) < 1.5)
        #expect(abs(series.last!.atl - 60) < 0.01)
        // Fatigue rises faster than fitness at the start → form is negative early on.
        #expect(series[5].tsb < 0)
    }

    @Test func weeksStartOnMondayAndIncludeEmptyWeeks() {
        let rides = [
            ride(1, day(2026, 11, 2), minutes: 60, np: 200),   // Monday
            ride(2, day(2026, 11, 8), minutes: 90, np: 180),   // Sunday same week
            ride(3, day(2026, 11, 17), minutes: 45, np: 220, sport: "Ride", trainer: false)
        ]
        let weeks = TrainingLoad.weeks(rides: rides, ftp: 250, from: day(2026, 11, 2), to: day(2026, 11, 17),
                                       calendar: calendar)
        #expect(weeks.count == 3)
        #expect(weeks[0].rides == 2)
        #expect(weeks[0].seconds == 150 * 60)
        #expect(weeks[0].indoorSeconds == 150 * 60)
        #expect(weeks[1].rides == 0)
        #expect(weeks[2].indoorSeconds == 0)
        #expect(calendar.component(.weekday, from: weeks[0].weekStart) == 2)
    }

    @Test func indoorDetection() {
        #expect(ride(1, .now, minutes: 1, sport: "VirtualRide", trainer: false).isIndoor)
        #expect(ride(1, .now, minutes: 1, sport: "Ride", trainer: true).isIndoor)
        #expect(!ride(1, .now, minutes: 1, sport: "Ride", trainer: false).isIndoor)
    }
}
