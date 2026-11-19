import Foundation
import Testing
@testable import IndoorCoachKit

/// Fremdsport aus Health (O6): geschätzte TSS fließt in CTL/ATL/Wochenumfang, aber nie in Leistungskurve, eFTP,
/// VO₂max oder die Soll/Ist-Zuordnung.
@Suite("Health-Fremdsport in der Belastung")
struct HealthForeignSportLoadTests {
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()
    let start = cal.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 7))!   // Montag

    func run(minutes: Int = 60, tss: Double = 80, hr: Double? = 150, at date: Date? = nil) -> RideSummary {
        var r = RideSummary(id: -42, name: "Laufen (Apple Watch)", sportType: "Run", startDate: date ?? start,
                            movingTime: minutes * 60, distance: 10_000, averageHeartrate: hr, maxHeartrate: hr.map { $0 + 20 })
        r.healthUUID = UUID().uuidString
        r.foreignSport = "running"
        r.estimatedTSS = tss
        return r
    }

    func powerRide(at date: Date) -> RideSummary {
        RideSummary(id: 5, name: "Sweet Spot", sportType: "VirtualRide", startDate: date, movingTime: 3600, distance: 30_000,
                    averageWatts: 200, weightedAverageWatts: 220, averageHeartrate: 140, maxHeartrate: 165, trainer: true)
    }

    @Test func estimatedTSSIsUsedAsIs() {
        let e = TrainingLoad.estimateTSS(for: run(tss: 83.5), ftp: 250, thresholdHeartRate: 160)
        #expect(e.tss == 83.5)
        #expect(e.source == .heartRate)
        #expect(TrainingLoad.estimateTSS(for: run(tss: 30, hr: nil), ftp: 250).source == .duration)
    }

    @Test func foreignSportFlowsIntoDailyAndWeeklyLoad() {
        let rides = [run(tss: 80), powerRide(at: start.addingTimeInterval(36_000))]
        let daily = TrainingLoad.dailyTSS(rides: rides, ftp: 250, calendar: Self.cal)
        let power = TrainingLoad.estimateTSS(for: rides[1], ftp: 250).tss
        #expect(abs((daily[Self.cal.startOfDay(for: start)] ?? 0) - (80 + power)) < 0.001)
        let weeks = TrainingLoad.weeks(rides: rides, ftp: 250, from: start, to: start, calendar: Self.cal)
        #expect(weeks.count == 1)
        #expect(weeks[0].rides == 2)
        #expect(weeks[0].seconds == 7200)
        #expect(abs(weeks[0].tss - (80 + power)) < 0.001)
        #expect(weeks[0].indoorSeconds == 3600)   // der Lauf zählt nicht als Indoor
    }

    @Test func foreignSportFeedsCTLAndATLEvenWithAnEffortFactor() {
        // 12 Fahrten mit Leistung und Puls → persönlicher Faktor TSS/Relative Effort existiert.
        let history = (1...12).map { i -> RideSummary in
            var r = powerRide(at: Self.cal.date(byAdding: .day, value: -i * 2, to: start)!)
            r.id = 100 + i
            return r
        }
        let hr = RelativeEffort.HeartRateProfile(resting: 50, max: 190)
        let withoutRun = FitnessFreshness.series(rides: history, ftp: 250, heartRate: hr, thresholdHeartRate: 160,
                                                 from: start.addingTimeInterval(-86_400 * 30), to: start, calendar: Self.cal)
        #expect(withoutRun.effortFactor != nil)
        let withRun = FitnessFreshness.series(rides: history + [run(tss: 90)], ftp: 250, heartRate: hr, thresholdHeartRate: 160,
                                              from: start.addingTimeInterval(-86_400 * 30), to: start, calendar: Self.cal)
        let day = Self.cal.startOfDay(for: start)
        let lastWith = withRun.points.first { $0.date == day }!
        let lastWithout = withoutRun.points.first { $0.date == day }!
        #expect(abs(lastWith.load - lastWithout.load - 90) < 0.001, "genau die geschätzte TSS, nicht Relative Effort × k")
        #expect(lastWith.fitness > lastWithout.fitness)
        #expect(lastWith.fatigue > lastWithout.fatigue)
    }

    @Test func foreignSportNeverReachesPowerAnalyses() {
        let r = run(minutes: 120, tss: 200)
        let from = start.addingTimeInterval(-86_400 * 30), to = start.addingTimeInterval(86_400)
        let withRun = PowerCurve.aggregate(rides: [r], from: from, to: to)
        #expect(withRun.points.isEmpty)
        #expect(FTPHistory.series(rides: [r], now: start.addingTimeInterval(86_400)).isEmpty)
        var profile = AthleteProfile()
        profile.ftp = 250; profile.weightKg = 75
        let reference = VO2max.estimate(curve: PowerCurve.aggregate(rides: [], from: from, to: to), profile: profile)
        #expect(VO2max.estimate(curve: withRun, profile: profile) == reference)
        #expect(r.foreignSport != nil && r.powerCurve == nil && r.averageWatts == nil)
    }

    // MARK: RideMerge

    @Test func healthRideIsEnrichedByALaterRideThatOverlapsIt() {
        var health = RideSummary(id: -7, name: "Radfahren (Apple Watch)", sportType: "Ride", startDate: start, movingTime: 3600,
                                 distance: 0, averageHeartrate: 140, maxHeartrate: 160)
        health.healthUUID = UUID().uuidString
        // Der Trainer-Start liegt 8 Minuten später: außerhalb des 5-Minuten-Fensters, aber > 50 % Überlappung.
        var fit = RideSummary(id: -99, name: "Sweet Spot", sportType: "VirtualRide", startDate: start.addingTimeInterval(480),
                              movingTime: 3300, distance: 30_000, averageWatts: 200, weightedAverageWatts: 215, trainer: true)
        fit.powerCurve = [300: 250, 1200: 230]
        #expect(RideMerge.decide(fit, existing: [health]) == .enrich(-7))
        let merged = RideMerge.enriched(health, with: fit)
        #expect(merged.name == "Sweet Spot")
        #expect(merged.sportType == "VirtualRide")
        #expect(merged.trainer)
        #expect(merged.healthUUID == nil && merged.estimatedTSS == nil && merged.foreignSport == nil)
        #expect(merged.powerCurve?[1200] == 230)
        #expect(merged.averageHeartrate == 140, "Puls aus Health bleibt, wenn die Fahrt keinen mitbringt")
    }

    @Test func aSummaryRideAlsoReplacesAHealthRideInsteadOfBeingSkipped() {
        var health = RideSummary(id: -7, name: "Radfahren (Apple Watch)", sportType: "Ride", startDate: start, movingTime: 3600, distance: 0)
        health.healthUUID = UUID().uuidString
        let strava = RideSummary(id: 123, name: "Rolle", sportType: "VirtualRide", startDate: start.addingTimeInterval(60),
                                 movingTime: 3500, distance: 30_000, averageWatts: 190, trainer: true)
        #expect(RideMerge.decide(strava, existing: [health]) == .enrich(-7))
    }

    @Test func incomingHealthRideIsOnlyMatchedByItsOwnID() {
        let other = RideSummary(id: 1, name: "Fahrt", sportType: "Ride", startDate: start, movingTime: 3600, distance: 0)
        var health = RideSummary(id: -7, name: "Radfahren (Apple Watch)", sportType: "Ride", startDate: start.addingTimeInterval(60),
                                 movingTime: 3600, distance: 0)
        health.healthUUID = UUID().uuidString
        #expect(RideMerge.decide(health, existing: [other]) == .insert, "die Überlappung hat HealthImport vorher entschieden")
    }
}
