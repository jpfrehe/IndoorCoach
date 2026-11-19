import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

/// Health-Quelle für Tests: liefert Workouts inkrementell (Anker = Anzahl gelieferter), kennt Löschungen und zählt Aufrufe.
final class FakeHealthSource: HealthDataSource, @unchecked Sendable {
    private let lock = NSLock()
    private var all: [HealthWorkout]
    private var pendingDeleted: [UUID] = []
    private var handler: (@Sendable () -> Void)?
    private(set) var workoutCalls = 0
    /// Zeitfenster-Abfragen (`workouts(in:)`), nur diese darf der Export/„Verbundene Quellen“ stellen.
    private(set) var rangeRequests: [ClosedRange<Date>] = []
    private(set) var observerRegistrations = 0
    var weightMean: Double?
    var heartRate: RideSeconds?
    let isAvailable = true

    init(_ workouts: [HealthWorkout] = [], weight: Double? = nil) { all = workouts; weightMean = weight }

    func add(_ w: HealthWorkout) { lock.withLock { all.append(w) } }
    func delete(_ id: UUID) { lock.withLock { pendingDeleted.append(id); all.removeAll { $0.uuid == id } } }
    func fire() { let h = lock.withLock { handler }; h?() }

    func authorizationStatus(for types: Set<HealthReadType>) async -> HealthAuthorizationStatus { .requested }
    func requestReadAuthorization(_ types: Set<HealthReadType>) async throws {}
    func workouts(since anchor: HealthAnchor?) async throws -> HealthWorkoutChanges {
        lock.withLock {
            workoutCalls += 1
            let seen = anchor.flatMap { String(data: $0.data, encoding: .utf8) }.flatMap(Int.init) ?? 0
            let deleted = pendingDeleted
            pendingDeleted = []
            return HealthWorkoutChanges(added: Array(all.dropFirst(seen)), deleted: deleted,
                                        anchor: HealthAnchor(data: Data(String(all.count).utf8)))
        }
    }
    func workouts(in range: ClosedRange<Date>) async throws -> [HealthWorkout] {
        lock.withLock {
            rangeRequests.append(range)
            return all.filter { $0.end >= range.lowerBound && $0.start <= range.upperBound }
        }
    }
    func heartRateSeconds(for workout: HealthWorkout) async throws -> RideSeconds? { heartRate }
    func dailyValues(_ metric: HealthMetric, in range: ClosedRange<Date>) async throws -> [HealthDaily] { [] }
    func bodyMass7DayMean(asOf: Date, source: HealthSourceRef?) async throws -> Double? { weightMean }
    func enableBackgroundDeliveryForWorkouts(_ onChange: @escaping @Sendable () -> Void) async throws {
        lock.withLock { handler = onChange; observerRegistrations += 1 }
    }
}

@Suite("AppModel+Health")
@MainActor
struct AppModelHealthTests {
    static var keepAlive: [ModelContainer] = []

    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func makeModel(source: FakeHealthSource, suite: String = "health-\(UUID().uuidString)") throws -> (AppModel, UserDefaults) {
        let container = try AppEnvironment.makeContainer(inMemory: true)
        Self.keepAlive.append(container)
        let defaults = UserDefaults(suiteName: suite)!
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults,
                             transport: RoutingTransport { _ in (200, Data("{}".utf8)) })
        model.healthSource = source
        return (model, defaults)
    }

    /// Zweites Modell auf denselben Defaults und demselben Store (App-Neustart).
    func relaunch(_ model: AppModel, _ defaults: UserDefaults) -> AppModel {
        let m = AppModel(context: model.context, secrets: InMemorySecretStore(), defaults: defaults,
                         transport: RoutingTransport { _ in (200, Data("{}".utf8)) })
        m.healthSource = model.healthSource
        return m
    }

    func workout(_ type: String, start: TimeInterval = -7200, minutes: Double = 60, hr: Double? = nil, own: Bool = false,
                 source: String = "Apple Watch") -> HealthWorkout {
        HealthWorkout(uuid: UUID(), start: now.addingTimeInterval(start), end: now.addingTimeInterval(start + minutes * 60),
                      activityTypeName: type, sourceName: source, sourceBundleID: "bundle.\(source)", isOwnSource: own,
                      avgHR: hr, maxHR: hr.map { $0 + 20 }, energyKcal: nil)
    }

    func insertRide(_ model: AppModel, id: Int = 11, start: TimeInterval = -7200, minutes: Int = 60, hr: Double? = nil, curve: Bool = false) {
        var r = RideSummary(id: id, name: "Sweet Spot", sportType: "VirtualRide", startDate: now.addingTimeInterval(start),
                            movingTime: minutes * 60, distance: 30_000, averageWatts: 200, weightedAverageWatts: 215,
                            averageHeartrate: hr, maxHeartrate: hr.map { $0 + 25 }, trainer: true)
        if curve { r.powerCurve = [300: 260, 1200: 240] }
        model.mergeImportedRides([r])
    }

    func rides(_ model: AppModel) -> [StoredRide] {
        ((try? model.context.fetch(FetchDescriptor<StoredRide>(sortBy: [SortDescriptor(\.startDate)]))) ?? []).filter { !$0.isDemo }
    }

    // MARK: Aktivierung

    @Test func nothingHappensUntilHealthIsEnabled() async throws {
        let source = FakeHealthSource([workout("running", hr: 150)])
        let (model, _) = try makeModel(source: source)
        #expect(!model.healthEnabled)
        let result = await model.syncHealth(now: now)
        #expect(result == HealthSyncResult())
        #expect(source.workoutCalls == 0)
        #expect(rides(model).isEmpty)
    }

    @Test func enablingPersistsRegistersTheObserverAndSyncs() async throws {
        let source = FakeHealthSource([workout("running", hr: 150)])
        let (model, defaults) = try makeModel(source: source)
        await model.setHealthEnabled(true)
        #expect(model.healthEnabled)
        #expect(source.observerRegistrations == 1)
        #expect(rides(model).count == 1)
        #expect(relaunch(model, defaults).healthEnabled)
        await model.setHealthEnabled(false)
        #expect(!model.healthEnabled)
        #expect(!relaunch(model, defaults).healthEnabled)
        #expect(rides(model).count == 1, "ausschalten löscht nichts")
    }

    @Test func observerCallbackTriggersASync() async throws {
        let source = FakeHealthSource()
        let (model, _) = try makeModel(source: source)
        await model.setHealthEnabled(true)
        source.add(workout("running", hr: 150))
        source.fire()
        for _ in 0..<100 where rides(model).isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(rides(model).count == 1)
    }

    // MARK: Aerobe Sportarten

    @Test func runBecomesAStoredRideWithEstimatedTSS() async throws {
        let source = FakeHealthSource([workout("running", hr: 148)])
        let (model, _) = try makeModel(source: source)
        model.profile.thresholdHeartRate = 160
        await model.setHealthEnabled(true)
        let ride = try #require(rides(model).first)
        #expect(ride.sourceRaw == "appleHealth")
        #expect(ride.healthUUID != nil)
        #expect(ride.foreignSport == "running")
        #expect(ride.sportType == "Run")
        #expect(ride.stravaID < 0)
        #expect(ride.movingTime == 3600)
        #expect(ride.name.contains("Laufen") && ride.name.contains("Apple Watch"))
        #expect(abs((ride.estimatedTSS ?? 0) - pow(148.0 / 160.0, 2) * 100) < 0.001)
        #expect(ride.averageHeartrate == 148)
        #expect(!ride.trainer)
        // Es zählt in der Belastung der Rad-PMC …
        let series = model.fitnessSeries(rides: model.allRides(), now: now)
        #expect((series.points.map(\.load).max() ?? 0) > 80)
    }

    @Test func runWithoutHeartRateUsesTheSportFactor() async throws {
        let (model, _) = try makeModel(source: FakeHealthSource([workout("running", minutes: 45)]))
        await model.setHealthEnabled(true)
        #expect(rides(model).first?.estimatedTSS == 45)
    }

    @Test func syncIsIncrementalAndNeverDuplicates() async throws {
        let source = FakeHealthSource([workout("running", hr: 150)])
        let (model, defaults) = try makeModel(source: source)
        await model.setHealthEnabled(true)
        await model.syncHealth(now: now)
        #expect(rides(model).count == 1)
        source.add(workout("hiking", start: -90_000, minutes: 120))
        let r = await model.syncHealth(now: now)
        #expect(r.imported == 1)
        #expect(rides(model).count == 2)
        // Anker verloren (z. B. neu installiert): dieselben Workouts kommen nochmal, die Liste fängt das ab.
        HealthAnchorStore(defaults: defaults).save(nil, for: .workouts)
        let again = await model.syncHealth(now: now)
        #expect(again.imported == 0)
        #expect(rides(model).count == 2)
    }

    @Test func ownSourceAndIgnoredSportsAreNotImported() async throws {
        let source = FakeHealthSource([workout("running", own: true), workout("yoga")])
        let (model, _) = try makeModel(source: source)
        await model.setHealthEnabled(true)
        #expect(rides(model).isEmpty)
        #expect(model.healthCandidates.isEmpty)
    }

    @Test func foreignSportDoesNotCompleteAPlannedWorkout() async throws {
        let (model, _) = try makeModel(source: FakeHealthSource([workout("running", start: -3600, hr: 150)]))
        let day = Calendar.current.startOfDay(for: now)
        let planned = PlannedWorkoutProposal(date: day, definition: WorkoutDefinition(title: "Grundlage", type: .endurance, summary: "", segments: []),
                                             rationale: "")
        model.context.insert(StoredWorkout(proposal: planned, source: .manual, weekFocus: nil))
        await model.setHealthEnabled(true)
        model.linkCompletedWorkouts()
        let workouts = try model.context.fetch(FetchDescriptor<StoredWorkout>())
        #expect(workouts.first?.status == .planned)
        #expect(workouts.first?.linkedRideID == nil)
    }

    // MARK: Rad und Überlappung

    @Test func realOutdoorRideCountsAsANormalRide() async throws {
        let source = FakeHealthSource([workout("cycling", start: -20_000, minutes: 150, hr: 135)])
        let (model, _) = try makeModel(source: source)
        insertRide(model, id: 11, start: -3600, minutes: 40)
        await model.setHealthEnabled(true)
        let health = try #require(rides(model).first { $0.healthUUID != nil })
        #expect(health.sportType == "Ride")
        #expect(health.foreignSport == nil)
        #expect(health.estimatedTSS == nil)
        #expect(!health.trainer)
        #expect(health.summary.isIndoor == false)
        #expect(rides(model).count == 2)
    }

    @Test func overlappingHealthWorkoutIsMergedAndExplained() async throws {
        let source = FakeHealthSource([workout("cycling", start: -7200 - 240, hr: 141, source: "Garmin Connect")])
        let (model, _) = try makeModel(source: source)
        insertRide(model, id: 11, hr: nil, curve: true)
        let result = await { await model.setHealthEnabled(true); return await model.syncHealth(now: now) }()
        #expect(result.imported == 0)
        let all = rides(model)
        #expect(all.count == 1)
        let ride = try #require(all.first)
        #expect(ride.healthUUID == nil)
        #expect(ride.mergedHealthUUID != nil)
        #expect(ride.healthNote?.contains("Garmin Connect") == true)
        #expect(ride.averageHeartrate == 141, "fehlender Puls wird aus Health ergänzt")
        #expect(model.allRides().count == 1)
    }

    @Test func fitHeartRateIsNotOverwrittenByHealth() async throws {
        let source = FakeHealthSource([workout("cycling", start: -7200 - 120, hr: 99)])
        let (model, _) = try makeModel(source: source)
        insertRide(model, id: 11, hr: 150, curve: true)
        await model.setHealthEnabled(true)
        #expect(rides(model).first?.averageHeartrate == 150)
        #expect(rides(model).first?.mergedHealthUUID != nil)
    }

    @Test func healthBeatsTheMyWhooshListHeartRate() async throws {
        let source = FakeHealthSource([workout("cycling", start: -7200, hr: 143)])
        let (model, _) = try makeModel(source: source)
        insertRide(model, id: -5, hr: 120, curve: false)    // Listeneintrag ohne Sekundendaten
        await model.setHealthEnabled(true)
        #expect(rides(model).first?.averageHeartrate == 143)
    }

    @Test func mergeCanBeUndoneKeepingTheHealthWorkoutAsItsOwnRide() async throws {
        let source = FakeHealthSource([workout("cycling", start: -7200 - 240, hr: 141)])
        let (model, defaults) = try makeModel(source: source)
        insertRide(model, id: 11, hr: 150, curve: true)
        await model.setHealthEnabled(true)
        let target = try #require(rides(model).first)
        #expect(target.mergedHealthUUID != nil)
        model.keepHealthWorkoutSeparate(rideID: target.stravaID)
        let all = rides(model)
        #expect(all.count == 2)
        let original = try #require(all.first { $0.stravaID == 11 })
        #expect(original.mergedHealthUUID == nil && original.healthNote == nil)
        let own = try #require(all.first { $0.healthUUID != nil })
        #expect(own.sportType == "Ride")
        // Beim nächsten Sync (und nach Neustart) bleibt es getrennt.
        await model.syncHealth(now: now)
        await relaunch(model, defaults).syncHealth(now: now)
        #expect(rides(model).count == 2)
    }

    @Test func aLaterFitRideAbsorbsAnAlreadyImportedHealthRide() async throws {
        let source = FakeHealthSource([workout("cycling", start: -7200, hr: 141)])
        let (model, _) = try makeModel(source: source)
        await model.setHealthEnabled(true)
        #expect(rides(model).count == 1 && rides(model).first?.healthUUID != nil)
        insertRide(model, id: 11, start: -7200 + 480, minutes: 55, hr: nil, curve: true)
        let all = rides(model)
        #expect(all.count == 1, "keine Dublette")
        let ride = try #require(all.first)
        #expect(ride.name == "Sweet Spot")
        #expect(ride.healthUUID == nil && ride.mergedHealthUUID != nil && ride.healthNote != nil)
        #expect(ride.powerCurve?[1200] == 240)
        #expect(ride.averageHeartrate == 141)
        // Wird das Health-Workout später gelöscht, bleibt die Fahrt.
        source.delete(UUID(uuidString: ride.mergedHealthUUID!)!)
        await model.syncHealth(now: now)
        #expect(rides(model).count == 1)
    }

    // MARK: Kraft → Annotations-Kandidaten

    @Test func strengthBecomesAnOpenCandidateThatSurvivesARestart() async throws {
        let source = FakeHealthSource([workout("traditionalStrengthTraining", minutes: 52, hr: 118, source: "Hevy")])
        let (model, defaults) = try makeModel(source: source)
        await model.setHealthEnabled(true)
        #expect(rides(model).isEmpty)
        let candidate = try #require(model.healthCandidates.first)
        #expect(candidate.sourceName == "Hevy")
        #expect(candidate.durationMinutes == 52)
        #expect(candidate.title == "Krafttraining")
        let again = relaunch(model, defaults)
        #expect(again.healthCandidates.map(\.uuid) == [candidate.uuid])
    }

    @Test func annotatingACandidateCreatesTheStrengthSessionAndClosesTheCard() async throws {
        let w = workout("traditionalStrengthTraining", minutes: 52, hr: 118, source: "Hevy")
        let (model, _) = try makeModel(source: FakeHealthSource([w]))
        await model.setHealthEnabled(true)
        let row = try #require(model.annotateHealthCandidate(w.uuid, hardness: 7, legs: .heavy))
        #expect(row.healthUUID == w.uuid.uuidString)
        #expect(row.exertion == 7)
        #expect(row.durationSeconds == 52 * 60)
        #expect(model.healthCandidates.isEmpty)
        #expect(model.strengthSessions().count == 1)
        await model.syncHealth(now: now)
        #expect(model.healthCandidates.isEmpty && model.strengthSessions().count == 1)
    }

    @Test func climbingAnnotationKeepsItsSport() async throws {
        let w = workout("climbing", minutes: 70)
        let (model, _) = try makeModel(source: FakeHealthSource([w]))
        await model.setHealthEnabled(true)
        let row = try #require(model.annotateHealthCandidate(w.uuid, hardness: 6, legs: nil))
        #expect(row.sportName == "climbing")
        #expect(row.feedsMuscleTrack)
    }

    @Test func dismissedCandidateStaysGone() async throws {
        let w = workout("traditionalStrengthTraining", hr: 110)
        let source = FakeHealthSource([w])
        let (model, defaults) = try makeModel(source: source)
        await model.setHealthEnabled(true)
        model.dismissHealthCandidate(w.uuid)
        #expect(model.healthCandidates.isEmpty)
        HealthAnchorStore(defaults: defaults).save(nil, for: .workouts)
        await model.syncHealth(now: now)
        #expect(model.healthCandidates.isEmpty)
        #expect(model.strengthSessions().isEmpty)
    }

    @Test func strengthWorkoutOverlappingAStrengthSessionIsMergedAndSuppliesHeartRate() async throws {
        let source = FakeHealthSource([workout("traditionalStrengthTraining", start: -7200 + 120, minutes: 50, hr: 120)])
        source.heartRate = RideSeconds(power: Array(repeating: 0, count: 3000), heartRate: (0..<3000).map { _ in UInt8(120) })
        let (model, _) = try makeModel(source: source)
        let own = try #require(model.saveStrengthManual(start: now.addingTimeInterval(-7200), durationMinutes: 52, exertion: 6,
                                                       legShare: .light, exercises: []))
        await model.setHealthEnabled(true)
        #expect(model.healthCandidates.isEmpty)
        #expect(own.heartRateSeries?.count == 3000, "fehlender Puls kommt aus Health")
        #expect(model.strengthSessions().count == 1)
    }

    // MARK: Löschen in Health

    @Test func deletedWorkoutsDisappearEverywhere() async throws {
        let run = workout("running", hr: 150)
        let strength = workout("traditionalStrengthTraining", start: -90_000)
        let annotated = workout("climbing", start: -180_000)
        let source = FakeHealthSource([run, strength, annotated])
        let (model, _) = try makeModel(source: source)
        await model.setHealthEnabled(true)
        _ = model.annotateHealthCandidate(annotated.uuid, hardness: 5, legs: nil)
        #expect(rides(model).count == 1 && model.healthCandidates.count == 1 && model.strengthSessions().count == 1)
        for w in [run, strength, annotated] { source.delete(w.uuid) }
        let result = await model.syncHealth(now: now)
        #expect(result.removed == 3)
        #expect(rides(model).isEmpty)
        #expect(model.healthCandidates.isEmpty)
        #expect(model.strengthSessions().isEmpty)
    }

    // MARK: Gewicht

    @Test func healthWeightReplacesTheProfileWeightOnlyForCalculations() async throws {
        let source = FakeHealthSource(weight: 82.3)
        let (model, defaults) = try makeModel(source: source)
        model.profile.weightKg = 78
        #expect(model.effectiveWeightKg == 78)
        await model.setHealthEnabled(true)
        #expect(model.effectiveWeightKg == 82.3)
        #expect(model.calculationProfile.weightKg == 82.3)
        #expect(model.profile.weightKg == 78, "das manuelle Gewicht bleibt unangetastet")
        #expect(relaunch(model, defaults).effectiveWeightKg == 82.3, "der letzte Wert gilt schon vor dem ersten Sync")
        await model.setHealthEnabled(false)
        #expect(model.effectiveWeightKg == 78)
    }

    @Test func implausibleOrMissingHealthWeightFallsBackToManual() async throws {
        let source = FakeHealthSource(weight: 3)
        let (model, _) = try makeModel(source: source)
        model.profile.weightKg = 78
        await model.setHealthEnabled(true)
        #expect(model.effectiveWeightKg == 78)
        source.weightMean = 80.1
        await model.syncHealth(now: now)
        #expect(model.effectiveWeightKg == 80.1)
        source.weightMean = nil
        await model.syncHealth(now: now)
        #expect(model.effectiveWeightKg == 78)
    }

    // MARK: Alle Daten löschen

    @Test func deleteAllDataForgetsTheHealthState() async throws {
        let source = FakeHealthSource([workout("traditionalStrengthTraining")], weight: 80)
        let (model, defaults) = try makeModel(source: source)
        await model.setHealthEnabled(true)
        #expect(!model.healthCandidates.isEmpty)
        await model.deleteAllData()
        #expect(!model.healthEnabled)
        #expect(model.healthCandidates.isEmpty)
        #expect(HealthAnchorStore(defaults: defaults).anchor(for: .workouts) == nil)
        #expect(model.effectiveWeightKg == model.profile.weightKg)
        let fresh = relaunch(model, defaults)
        #expect(!fresh.healthEnabled && fresh.healthCandidates.isEmpty)
    }

    // MARK: Indoor-Rad aus Health (Befund 5)

    @Test func indoorHealthCyclingIsImportedAsTrainerRideAndTakesThePhonePulse() async throws {
        var indoor = workout("cycling", start: -7200, minutes: 30, hr: 120)
        indoor.isIndoor = true
        var outdoor = workout("cycling", start: -86_400, minutes: 60, hr: 130)
        outdoor.isIndoor = false
        let named = workout("indoorCycling", start: -172_800, minutes: 45, hr: 125)
        let (model, _) = try makeModel(source: FakeHealthSource([indoor, outdoor, named]))
        model.healthEnabled = true
        await model.syncHealth(now: now)
        let rows = rides(model)
        #expect(rows.count == 3)
        #expect(rows.first { $0.startDate == indoor.start }?.trainer == true)
        #expect(rows.first { $0.startDate == outdoor.start }?.trainer == false)
        #expect(rows.first { $0.startDate == named.start }?.trainer == true)
        // iPhone-Puls aus der Aufzeichnung findet die Health-Radfahrt.
        let seconds = 1800
        let recording = RecordingResult(kind: .ride, title: "Rolle", startedAt: indoor.start, endedAt: indoor.start.addingTimeInterval(TimeInterval(seconds)),
                                        seconds: RideSeconds(power: [UInt16](repeating: 0, count: seconds), heartRate: [UInt8](repeating: 140, count: seconds)))
        let id = try #require(rows.first { $0.startDate == indoor.start }?.stravaID)
        #expect(model.finishRecording(recording) == .attached(rideID: id))
    }

    // MARK: Anker nur nach erfolgreichem Speichern (Befund 10)

    struct DiskFull: Error {}

    @Test func failedSaveKeepsAnchorAndLedgerSoNothingIsLost() async throws {
        let source = FakeHealthSource([workout("cycling", start: -7200, minutes: 45, hr: 130)])
        let (model, defaults) = try makeModel(source: source)
        model.healthEnabled = true
        model.saveOverride = { throw DiskFull() }
        let failed = await model.syncHealth(now: now)
        #expect(failed.imported == 0 && failed.merged == 0)
        #expect(HealthAnchorStore(defaults: defaults).anchor(for: .workouts) == nil, "Anker darf nicht vorrücken")
        #expect(model.loadHealthLedger().isEmpty)
        #expect(rides(model).isEmpty)
        #expect(model.banner?.isError == true)
        // Nächster Lauf: dasselbe Workout kommt erneut und wird jetzt übernommen.
        model.saveOverride = nil
        let ok = await model.syncHealth(now: now)
        #expect(ok.imported == 1)
        #expect(rides(model).count == 1)
        #expect(HealthAnchorStore(defaults: defaults).anchor(for: .workouts) != nil)
        #expect(model.loadHealthLedger().count == 1)
    }

    @Test func mergeWithoutTargetIsNotCountedAndFallsBackToOwnEntry() async throws {
        let (model, _) = try makeModel(source: FakeHealthSource())
        var ledger: [HealthLedgerEntry] = []
        let w = workout("cycling", start: -7200, minutes: 45, hr: 130)
        let merged = await model.mergeHealthWorkout(w, into: .ride(987_654), supplyHeartRate: true, ledger: &ledger)
        #expect(!merged)
        #expect(ledger.isEmpty, "kein Ledger-Eintrag „merged“ ohne Ziel")
    }
}
