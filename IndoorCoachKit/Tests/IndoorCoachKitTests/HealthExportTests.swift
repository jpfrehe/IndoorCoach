import Foundation
import Testing
@testable import IndoorCoachKit

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func candidate(_ sport: HealthExportSport = .strength, minutes: Double = 60, hr: [UInt8]? = [120, 130, 0, 140]) -> HealthExportCandidate {
    HealthExportCandidate(id: UUID(), sport: sport, activityTypeName: nil, start: t0, end: t0.addingTimeInterval(minutes * 60), heartRate: hr)
}

private func foreign(offsetMin: Double, minutes: Double, own: Bool = false) -> HealthWorkout {
    HealthWorkout(uuid: UUID(), start: t0.addingTimeInterval(offsetMin * 60), end: t0.addingTimeInterval((offsetMin + minutes) * 60),
                  activityTypeName: "running", sourceName: "Watch", sourceBundleID: "com.apple.health", isOwnSource: own,
                  avgHR: nil, maxHR: nil, energyKcal: nil)
}

private let allOn = HealthExportSettings(strength: true, other: true, cycling: true)

@Suite("Health-Export Regeln")
struct HealthExportRulesTests {
    @Test func defaultIsOff() {
        let s = HealthExportSettings()
        #expect(!s.anyEnabled)
        #expect(HealthExportRules.decide(candidate(), settings: s, existing: []) == .disabled)
        #expect(HealthExportRules.writeTypes(for: s).isEmpty)
    }

    @Test func perSportSwitch() {
        let s = HealthExportSettings(strength: true)
        #expect(HealthExportRules.decide(candidate(.strength), settings: s, existing: []) == .export)
        #expect(HealthExportRules.decide(candidate(.other), settings: s, existing: []) == .disabled)
        #expect(HealthExportRules.decide(candidate(.cycling), settings: s, existing: []) == .disabled)
    }

    @Test func writeTypesAreWorkoutAndHeartRateOnly() {
        #expect(HealthExportRules.writeTypes(for: HealthExportSettings(cycling: true)) == [.workout, .heartRate])
    }

    @Test func overlapOfHalfOrMoreBlocksExport() {
        // 60 min candidate; foreign workout covers 30 min = exactly 50 %.
        #expect(HealthExportRules.decide(candidate(), settings: allOn, existing: [foreign(offsetMin: 30, minutes: 60)]) == .overlaps)
        // 29 min = 48 %.
        #expect(HealthExportRules.decide(candidate(), settings: allOn, existing: [foreign(offsetMin: 31, minutes: 60)]) == .export)
    }

    @Test func overlapSumsAcrossWorkoutsAndIgnoresOwnOnes() {
        let two = [foreign(offsetMin: -10, minutes: 25), foreign(offsetMin: 35, minutes: 30)]   // 15 + 25 = 40 min
        #expect(HealthExportRules.decide(candidate(), settings: allOn, existing: two) == .overlaps)
        #expect(HealthExportRules.decide(candidate(), settings: allOn, existing: [foreign(offsetMin: 0, minutes: 60, own: true)]) == .export)
    }

    @Test func tooShortIsSkipped() {
        #expect(HealthExportRules.decide(candidate(minutes: 0.5), settings: allOn, existing: []) == .tooShort)
    }

    @Test func payloadCarriesHeartRateButNoPower() {
        let p = HealthExportRules.payload(for: candidate(.cycling))
        #expect(p.activityTypeName == "cycling")
        #expect(p.heartRate.map(\.bpm) == [120, 130, 140])          // 0 = gap
        #expect(p.heartRate[2].date == t0.addingTimeInterval(3))
        let labels = Mirror(reflecting: p).children.compactMap(\.label).joined(separator: ",").lowercased()
        #expect(!labels.contains("watt") && !labels.contains("power"))
    }

    @Test func activityTypes() {
        #expect(HealthExportRules.payload(for: candidate(.strength)).activityTypeName == "traditionalStrengthTraining")
        var other = candidate(.other)
        other.activityTypeName = "climbing"
        #expect(HealthExportRules.payload(for: other).activityTypeName == "climbing")
        #expect(HealthExportRules.payload(for: candidate(.other)).activityTypeName == "other")
    }
}

@Suite("Health-Export Service")
struct HealthExportServiceTests {
    private func makeService(_ writer: StubHealthWorkoutWriter = StubHealthWorkoutWriter()) -> (HealthExportService, StubHealthWorkoutWriter) {
        let defaults = UserDefaults(suiteName: "export-\(UUID().uuidString)")!
        return (HealthExportService(writer: writer, defaults: defaults), writer)
    }

    @Test func authorizationOnlyWhenSwitchingOn() async throws {
        let (service, writer) = makeService()
        #expect(service.settings == HealthExportSettings())
        try await service.setEnabled(.strength, false)
        #expect(writer.authorizationRequests.isEmpty)
        try await service.setEnabled(.strength, true)
        #expect(writer.authorizationRequests == [[.workout, .heartRate]])
        #expect(service.settings.strength)
    }

    @Test func switchOnFailsWithoutHealth() async {
        let (service, _) = makeService(StubHealthWorkoutWriter(isAvailable: false))
        await #expect(throws: HealthDataError.self) { try await service.setEnabled(.other, true) }
        #expect(!service.settings.other)
    }

    @Test func exportsOnceAndSkipsOverlap() async throws {
        let (service, writer) = makeService()
        try await service.setEnabled(.strength, true)
        let a = candidate(.strength)
        var b = candidate(.strength)
        b.start = t0.addingTimeInterval(7200)
        b.end = b.start.addingTimeInterval(3600)
        let result = await service.export([a, b], existing: [foreign(offsetMin: 120, minutes: 60)])
        #expect(result.exported == [a.id])
        #expect(result.skipped[b.id] == .overlaps)
        #expect(writer.saved.count == 1)
        // Second run: already exported -> not written again.
        let again = await service.export([a], existing: [])
        #expect(again.exported.isEmpty)
        #expect(writer.saved.count == 1)
    }

    @Test func nothingWrittenWhenOff() async {
        let (service, writer) = makeService()
        let result = await service.export([candidate()], existing: [])
        #expect(result.exported.isEmpty)
        #expect(writer.saved.isEmpty)
    }
}
