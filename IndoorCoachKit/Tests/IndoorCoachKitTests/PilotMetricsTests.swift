import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

@Suite("Pilot-Kennzahlen")
struct PilotMetricsTests {
    private func checkIn(skipped: Bool = false, offered: [CheckIn.Action] = [], chosen: CheckIn.Action? = nil) -> PilotMetrics.CheckInRecord {
        .init(skipped: skipped, offered: offered, chosen: chosen)
    }

    @Test func offersShownAndAcceptedPerKind() {
        let m = PilotMetrics.compute(.init(checkIns: [
            checkIn(offered: [.shorten(minutes: 20, easierBy: 10), .joker], chosen: .shorten(minutes: 20, easierBy: 10)),
            checkIn(offered: [.easier(percent: 10), .swapToBase], chosen: .swapToBase),
            checkIn(offered: [.shorten(minutes: 30, easierBy: 5)]),
            checkIn(skipped: true),
            checkIn(),
        ]))
        #expect(m.checkIns == 5)
        #expect(m.checkInsSkipped == 1)
        #expect(m.offers[.shorten] == .init(shown: 2, accepted: 1))
        #expect(m.offers[.easier] == .init(shown: 1, accepted: 0))
        #expect(m.offers[.swap] == .init(shown: 1, accepted: 1))
        #expect(m.offers[.joker] == .init(shown: 1, accepted: 0))
    }

    @Test func adjustedShareOfNotAsPlannedSessions() {
        let m = PilotMetrics.compute(.init(workouts: [
            .init(status: .done, adjusted: true), .init(status: .done, adjusted: false), .init(status: .planned, adjusted: false),
            .init(status: .skipped, adjusted: false), .init(status: .skipped, adjusted: false), .init(status: .skipped, adjusted: true),
        ]))
        #expect(m.notAsPlanned == 4)          // 1 adjusted done + 3 skipped
        #expect(m.adjusted == 2)
        #expect(m.adjustedShare == 0.5)
        #expect(PilotMetrics.compute(.init()).adjustedShare == nil)
    }

    @Test func warmupUsableOfTotalRecordingsAndStrength() {
        let ok = WarmupCheck(date: .now, refWatts: 140, hrMean: 120, valid: true, reason: nil, source: .measured)
        let bad = WarmupCheck(date: .now, refWatts: 140, hrMean: nil, valid: false, reason: "x", source: .measured)
        let m = PilotMetrics.compute(.init(warmupChecks: [ok, bad, ok], recordingGapSeconds: [0, 31, 30, 200],
                                           strength: [.init(hasExertion: true, hasLegShare: true), .init(hasExertion: true, hasLegShare: false),
                                                      .init(hasExertion: false, hasLegShare: true)]))
        #expect(m.warmupTotal == 3)
        #expect(m.warmupUsable == 2)
        #expect(m.recordings == 4)
        #expect(m.recordingsWithGap == 2)
        #expect(m.strengthTotal == 3)
        #expect(m.strengthComplete == 1)
    }

    @Test func linesContainOnlyCountsAndOmitMissingParts() {
        var input = PilotMetrics.Input()
        input.claudeConsent = true
        input.healthImported = 4
        input.healthMerged = 1
        input.guardShadowHits = 3
        input.guardShadowDays = 20
        let lines = PilotMetrics.compute(input).lines
        #expect(lines.first == "== Pilot-Kennzahlen ==")
        #expect(lines.contains("Claude-Einwilligung: ja"))
        #expect(lines.contains("Health-Workouts: 4 importiert, 1 zusammengeführt"))
        #expect(lines.contains("Trend-Wächter: Karte angezeigt an 0 Tagen, Schatten 3 Treffer an 20 Tagen"))
        #expect(!lines.contains { $0.contains("Plan-Feedback") })
        input.planFeedback = .init(up: 5, down: 2)
        #expect(PilotMetrics.compute(input).lines.contains("Plan-Feedback: 5 positiv, 2 negativ"))
        #expect(PilotMetrics.compute(.init()).lines.contains("Claude-Einwilligung: nein"))
    }

    @Test func quotasAreFormattedAsGermanPercent() {
        var input = PilotMetrics.Input()
        input.workouts = [.init(status: .skipped, adjusted: false), .init(status: .done, adjusted: true),
                          .init(status: .done, adjusted: true), .init(status: .skipped, adjusted: false)]
        let lines = PilotMetrics.compute(input).lines
        #expect(lines.contains("Angepasst an nicht wie geplant gefahrenen Einheiten: 2 von 4 (50 %)"))
    }

    @MainActor
    @Test func exportContainsNoHeartRateOrWeightValues() async throws {
        let container = try AppEnvironment.makeContainer(inMemory: true)
        let defaults = UserDefaults(suiteName: "pilot-\(UUID().uuidString)")!
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults)
        let ride = RideSummary(id: 77, name: "Geheim", sportType: "VirtualRide", startDate: .now, movingTime: 3600, distance: 30_000,
                               averageWatts: 187, weightedAverageWatts: 191, averageHeartrate: 143, maxHeartrate: 187, trainer: true)
        container.mainContext.insert(StoredRide(ride, isDemo: false))
        let strength = StrengthSession(start: .now, durationSeconds: 3000, exertion: 7, legShare: .heavy,
                                       exercises: [PerformedExercise(exerciseID: "squat", sets: 4, reps: 6, weightKg: 87)],
                                       templateName: "Beine-Geheim")
        container.mainContext.insert(StoredStrengthSession(session: strength))
        container.mainContext.insert(StoredCheckIn(day: .now, answers: .init(), offered: [.joker]))
        try container.mainContext.save()

        let report = await model.diagnosticsReport(since: .now.addingTimeInterval(-3600)) { _ in [] }
        #expect(report.contains("== Pilot-Kennzahlen =="))
        let section = report.components(separatedBy: "== Pilot-Kennzahlen ==").last ?? ""
        #expect(section.contains("Check-ins gesamt: 1"))
        #expect(section.contains("Krafteinheiten: 1 gesamt, 1 mit Härte und Beinen"))
        for forbidden in ["143", "187", "191", "87", "Geheim"] { #expect(!section.contains(forbidden)) }
    }
}
