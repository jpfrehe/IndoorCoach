import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

/// Befund 8: „angenommen (ERG)“ ist kein gemessener Wert. Eine gemeinsame `hasPower`-Regel, getrennte Trends,
/// und der Trend-Wächter sowie der Erholungskontext sehen nur gemessene Werte.
@Suite("Aufwärm-Check: angenommen vs. gemessen")
@MainActor
struct WarmupAssumedSeparationTests {
    static var keepAlive: [ModelContainer] = []
    static let ref = 140

    static func check(_ day: Int, hr: Double, source: WarmupCheck.Source) -> WarmupCheck {
        WarmupCheck(date: Date(timeIntervalSince1970: Double(day) * 86_400), refWatts: ref, hrMean: hr, valid: true, reason: nil, source: source)
    }

    @Test func hasPowerIsOneRuleForAllCallers() {
        let none = RideSeconds(power: [UInt16](repeating: 0, count: 3600), heartRate: [UInt8](repeating: 120, count: 3600))
        #expect(!none.hasPower)
        var sparse = [UInt16](repeating: 0, count: 3600)
        for i in 0..<30 { sparse[i * 100] = 150 }
        let some = RideSeconds(power: sparse, heartRate: nil)
        #expect(some.hasPower)
        // RecordingMerge und Aufwärm-Check entscheiden gleich.
        #expect(RecordingMerge.hasPower(some) == some.hasPower)
        #expect(RecordingMerge.hasPower(none) == none.hasPower)
        let def = WarmupCheckTests.definition
        let check = WarmupCheck.evaluate(date: .now, definition: def,
                                         seconds: RideSeconds(power: sparse + [UInt16](repeating: 0, count: 0),
                                                              heartRate: [UInt8](repeating: 120, count: 3600)),
                                         ftp: WarmupCheckTests.ftp, refWatts: WarmupCheckTests.ref)
        #expect(check?.source == .measured)   // vorhandene Watt-Sekunden gelten nie als „angenommen“
    }

    @Test func trendCanBeRestrictedToOneSource() {
        let checks = [Self.check(1, hr: 130, source: .measured), Self.check(2, hr: 128, source: .measured),
                      Self.check(3, hr: 126, source: .measured), Self.check(4, hr: 150, source: .assumedERG),
                      Self.check(5, hr: 152, source: .assumedERG)]
        let measured = WarmupCheck.trend(checks: checks, refWatts: Self.ref, source: .measured)
        #expect(measured.count == 3)
        #expect(measured.allMeasured)
        #expect(measured.direction == .falling)
        let assumed = WarmupCheck.trend(checks: checks, refWatts: Self.ref, source: .assumedERG)
        #expect(assumed.count == 2 && !assumed.allMeasured)
        #expect(assumed.direction == .notEnough)
    }

    @Test func trendGuardIgnoresAssumedChecks() {
        let measured = (1...4).map { Self.check($0, hr: 130, source: .measured) }
        // Ein angenommener Ausreißer als jüngster Wert darf den Wächter nicht auslösen.
        let withAssumed = measured + [Self.check(5, hr: 150, source: .assumedERG)]
        #expect(TrendGuard.warmupDelta(checks: withAssumed, refWatts: Self.ref) == TrendGuard.warmupDelta(checks: measured, refWatts: Self.ref))
        #expect(TrendGuard.warmupDelta(checks: withAssumed, refWatts: Self.ref) == 0)
        let onlyAssumed = (1...5).map { Self.check($0, hr: 130 + Double($0), source: .assumedERG) }
        #expect(TrendGuard.warmupDelta(checks: onlyAssumed, refWatts: Self.ref) == nil)
    }

    @Test func recoverySummaryUsesMeasuredTrendOnly() throws {
        let container = try AppEnvironment.makeContainer(inMemory: true)
        Self.keepAlive.append(container)
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(),
                             defaults: UserDefaults(suiteName: "wa-\(UUID().uuidString)")!)
        model.profile.ftp = WarmupCheckTests.ftp
        model.profile.warmupCheckWatts = WarmupCheckTests.ref
        let def = WarmupCheckTests.definition
        let workoutCount = 6
        // Sechs reine Puls-Fahrten (angenommene Leistung) mit steigendem Puls: 130 … 150 bpm.
        for i in 0..<workoutCount {
            let id = -100 - i
            let start = Date.now.addingTimeInterval(-Double(workoutCount - i) * 86_400)
            model.mergeImportedRides([RideSummary(id: id, name: "Rolle", sportType: "VirtualRide", startDate: start, movingTime: 3600,
                                                  distance: 0, trainer: true)])
            let hr = 118 + Double(i) * 6
            let seconds = WarmupCheckTests.ride(hr: hr, withPower: false)
            var d = FetchDescriptor<StoredRide>(predicate: #Predicate { $0.stravaID == id })
            d.fetchLimit = 1
            let row = try #require(container.mainContext.fetch(d).first)
            row.secondsData = seconds.encoded()
            let workout = StoredWorkout(proposal: PlannedWorkoutProposal(date: start, definition: def, rationale: ""), source: .manual, weekFocus: nil)
            workout.linkedRideID = id
            container.mainContext.insert(workout)
        }
        try container.mainContext.save()
        model.invalidateWarmupChecks()
        let rides = model.allRides()
        #expect(rides.compactMap { model.warmupCheck(for: $0) }.allSatisfy { $0.source == .assumedERG })
        // Angenommene Werte stehen in ihrem eigenen Trend, nicht im gemessenen.
        #expect(model.warmupTrend(rides: rides).count == 0)
        let assumed = model.warmupTrend(rides: rides, source: .assumedERG)
        #expect(assumed.count == workoutCount)
        #expect(assumed.direction == .rising)
        // Erholungskontext: kein Aufwärm-Trend aus angenommenen Werten.
        model.grantClaudeConsent()
        #expect(model.recoverySummary()?.warmup == nil)
    }
}
