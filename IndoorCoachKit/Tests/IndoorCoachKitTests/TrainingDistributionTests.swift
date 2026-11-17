import Foundation
import Testing
@testable import IndoorCoachKit

private let now = Date(timeIntervalSince1970: 1_794_000_000)

private func ride(_ id: Int, daysAgo: Double, minutes: Int = 60, avg: Double? = nil, np: Double? = nil) -> RideSummary {
    RideSummary(id: id, name: "r", sportType: "VirtualRide", startDate: now.addingTimeInterval(-daysAgo * 86_400),
                movingTime: minutes * 60, distance: 0, averageWatts: avg, weightedAverageWatts: np, trainer: true)
}

@Suite("Training distribution")
struct TrainingDistributionTests {
    @Test func intensityFactorFromNPOrAverage() throws {
        #expect(abs(try #require(TrainingDistribution.intensityFactor(for: ride(1, daysAgo: 1, np: 200), ftp: 250)) - 0.8) < 1e-9)
        #expect(abs(try #require(TrainingDistribution.intensityFactor(for: ride(1, daysAgo: 1, avg: 200), ftp: 250)) - 0.84) < 1e-9)
        #expect(TrainingDistribution.intensityFactor(for: ride(1, daysAgo: 1), ftp: 250) == nil)
        #expect(TrainingDistribution.intensityFactor(for: ride(1, daysAgo: 1, np: 200), ftp: 0) == nil)
    }

    @Test func bandBoundaries() {
        #expect(TrainingDistribution.band(forIF: 0.7499) == .base)
        #expect(TrainingDistribution.band(forIF: 0.75) == .tempo)
        #expect(TrainingDistribution.band(forIF: 0.9499) == .tempo)
        #expect(TrainingDistribution.band(forIF: 0.95) == .threshold)
        #expect(TrainingDistribution.band(forIF: nil) == .unknown)
    }

    @Test func sharesWeightedByTimeAndWindowed() {
        let rides = [
            ride(1, daysAgo: 2, minutes: 120, np: 150),    // base 2 h
            ride(2, daysAgo: 5, minutes: 30, np: 210),     // tempo 0.5 h
            ride(3, daysAgo: 8, minutes: 30, np: 250),     // threshold 0.5 h
            ride(4, daysAgo: 9, minutes: 60),              // unknown 1 h
            ride(5, daysAgo: 40, minutes: 600, np: 150),   // outside 4 weeks
        ]
        let r = TrainingDistribution.distribution(rides: rides, ftp: 250, weeks: 4, now: now)
        #expect(r.totalSeconds == 4 * 3600)
        #expect(abs(r.share(.base) - 0.5) < 1e-9)
        #expect(abs(r.share(.tempo) - 0.125) < 1e-9)
        #expect(abs(r.share(.threshold) - 0.125) < 1e-9)
        #expect(abs(r.share(.unknown) - 0.25) < 1e-9)
        let wide = TrainingDistribution.distribution(rides: rides, ftp: 250, weeks: 12, now: now)
        #expect(wide.totalSeconds == 14 * 3600)
    }

    @Test func emptyWindow() {
        let r = TrainingDistribution.distribution(rides: [], ftp: 250, weeks: 4, now: now)
        #expect(r.totalSeconds == 0)
        #expect(r.share(.base) == 0)
        #expect(TrainingDistribution.advice(r).contains("Noch keine Fahrten"))
    }

    @Test func adviceTexts() {
        let good = TrainingDistribution.distribution(
            rides: [ride(1, daysAgo: 1, minutes: 81, np: 150), ride(2, daysAgo: 2, minutes: 19, np: 250)],
            ftp: 250, weeks: 4, now: now)
        #expect(TrainingDistribution.advice(good) == "81 % Grundlage – passt zum Winter")
        let hard = TrainingDistribution.distribution(
            rides: [ride(1, daysAgo: 1, minutes: 40, np: 150), ride(2, daysAgo: 2, minutes: 60, np: 250)],
            ftp: 250, weeks: 4, now: now)
        #expect(TrainingDistribution.advice(hard) == "Viel Intensität: plane mehr lockere Einheiten")
        let blind = TrainingDistribution.distribution(
            rides: [ride(1, daysAgo: 1, minutes: 60), ride(2, daysAgo: 2, minutes: 30, np: 150)],
            ftp: 250, weeks: 4, now: now)
        #expect(TrainingDistribution.advice(blind).contains("fehlt die Leistung"))
    }
}
