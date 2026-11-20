import Foundation
import Testing
@testable import IndoorCoachKit

private let start = Date(timeIntervalSince1970: 1_794_000_000)

private func ride(minutes: Int, np: Double = 200) -> RideSummary {
    RideSummary(id: minutes, name: "r", sportType: "VirtualRide", startDate: start, movingTime: minutes * 60,
                distance: 30_000, averageWatts: np, weightedAverageWatts: np, averageHeartrate: 140, trainer: true)
}

private func strength(minutes: Int, exertion: Int?) -> StrengthSession {
    StrengthSession(start: start, durationSeconds: minutes * 60, exertion: exertion)
}

@Suite("History week header")
struct HistoryWeekSummaryTests {
    @Test func ridesOnlyShowTimeAndTSS() {
        let text = HistoryWeekSummary.text(rides: [ride(minutes: 60, np: 200)], strength: [], ftp: 200, thresholdHeartRate: nil)
        #expect(text == "1:00 h · TSS 100")
    }

    @Test func strengthOnlyShowsTimeAndMuscleLoadInsteadOfZeroTSS() {
        let text = HistoryWeekSummary.text(rides: [], strength: [strength(minutes: 45, exertion: 7), strength(minutes: 30, exertion: 5)],
                                           ftp: 200, thresholdHeartRate: nil)
        #expect(text == "1:15 h · Last 465")
    }

    @Test func mixedWeekAddsTimeAndShowsBothTracks() {
        let text = HistoryWeekSummary.text(rides: [ride(minutes: 60, np: 200)], strength: [strength(minutes: 30, exertion: 6)],
                                           ftp: 200, thresholdHeartRate: nil)
        #expect(text == "1:30 h · TSS 100 · Last 180")
    }

    @Test func strengthWithoutExertionShowsOnlyTime() {
        let text = HistoryWeekSummary.text(rides: [], strength: [strength(minutes: 40, exertion: nil)], ftp: 200, thresholdHeartRate: nil)
        #expect(text == "40 min")
    }
}
