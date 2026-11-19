import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

@MainActor
@Suite("Aufzeichnung an Fahrt hängen (B40)")
struct RecordingAttachTests {
    let container: ModelContainer
    let model: AppModel
    let defaults: UserDefaults
    let t0 = Date(timeIntervalSince1970: 1_794_000_000)

    init() throws {
        container = try ModelContainer(for: StoredRide.self, StoredWorkout.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        defaults = UserDefaults(suiteName: "rec-\(UUID().uuidString)")!
        model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults,
                         transport: RoutingTransport { _ in (500, Data()) }, myWhooshStore: InMemoryMyWhooshSessionStore())
    }

    func ride(id: Int = 77, offset: TimeInterval = 0, duration: Int = 1800) -> RideSummary {
        RideSummary(id: id, name: "MyWhoosh", sportType: "VirtualRide", startDate: t0.addingTimeInterval(offset),
                    movingTime: duration, distance: 0, trainer: true)
    }

    func result(duration: Int = 1800, bpm: UInt8 = 130, planned: UUID? = nil, start: Date? = nil) -> RecordingResult {
        let s = start ?? t0
        return RecordingResult(kind: .ride, title: "Sweet Spot", startedAt: s, endedAt: s.addingTimeInterval(TimeInterval(duration)),
                               seconds: RideSeconds(power: [UInt16](repeating: 0, count: duration),
                                                    heartRate: [UInt8](repeating: bpm, count: duration)),
                               plannedWorkoutID: planned)
    }

    func storedRide(_ id: Int) throws -> StoredRide {
        try #require(try container.mainContext.fetch(FetchDescriptor<StoredRide>()).first { $0.stravaID == id })
    }

    @Test("Passende Fahrt ohne Sekundendaten bekommt die Pulsspur, Leistung bleibt 0, Quelle ERG")
    func attachToListRide() throws {
        model.mergeImportedRides([ride()])
        let outcome = model.finishRecording(result())
        #expect(outcome == .attached(rideID: 77))
        let seconds = try #require(model.rideSeconds(id: 77))
        #expect(seconds.heartRate?.first == 130)
        #expect(!RecordingMerge.hasPower(seconds))
        #expect(model.recordingSource(for: ride()) == .assumedERG)
        #expect(try storedRide(77).powerCurveData == nil)
        let zones = try #require(model.zoneTimes(for: ride()))
        #expect(zones.powerTotal == 0)
        #expect(zones.heartTotal == 1800)
    }

    @Test("Ohne echte Watt gibt es kein Soll/Ist und keine Leistungskurve")
    func noComplianceFromAssumedWatts() throws {
        model.mergeImportedRides([ride()])
        let def = WorkoutDefinition(title: "SS", type: .sweetSpot, summary: "", segments: [
            .warmup(5, from: 0.5, to: 0.7), .steady(20, at: 0.9)
        ])
        let workout = StoredWorkout(proposal: PlannedWorkoutProposal(date: t0, definition: def, rationale: ""), source: .manual, weekFocus: nil)
        container.mainContext.insert(workout)
        model.finishRecording(result(planned: workout.id))
        #expect(workout.linkedRideID == 77)
        #expect(workout.status == .done)
        #expect(model.intervalCompliance(for: workout) == nil)
        #expect(try storedRide(77).powerCurveData == nil)
        #expect(try storedRide(77).weightedAverageWatts == nil)
    }

    @Test("Echte Leistung wird nie überschrieben, Quelle gemessen")
    func keepsMeasuredPower() throws {
        let row = StoredRide(ride())
        row.secondsData = RideSeconds(power: [UInt16](repeating: 200, count: 1800), heartRate: nil).encoded()
        container.mainContext.insert(row)
        #expect(model.finishRecording(result()) == .attached(rideID: 77))
        let seconds = try #require(model.rideSeconds(id: 77))
        #expect(seconds.power.allSatisfy { $0 == 200 })
        #expect(seconds.heartRate?.first == 130)
        #expect(model.recordingSource(for: ride()) == .measured)
    }

    @Test("Ohne Fahrt wartet die Aufzeichnung und wird beim nächsten Import zugeordnet")
    func pendingThenImport() throws {
        #expect(model.finishRecording(result()) == .pending)
        #expect(model.pendingRecordings.count == 1)
        // Neustart: Zustand kommt aus den Defaults.
        let again = AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults,
                             transport: RoutingTransport { _ in (500, Data()) }, myWhooshStore: InMemoryMyWhooshSessionStore())
        again.pendingRecordingsURL = model.pendingRecordingsURL   // gleiche Datei wie vor dem „Neustart“
        #expect(again.pendingRecordings.count == 1)
        again.mergeImportedRides([ride(offset: 90)])
        #expect(again.pendingRecordings.isEmpty)
        #expect(again.rideSeconds(id: 77)?.heartRate?.contains(130) == true)
        #expect(again.recordingSource(for: ride(offset: 90)) == .assumedERG)
    }

    @Test("Eine andere Fahrt am Tag, die nicht passt, lässt die Aufzeichnung warten")
    func pendingStaysWhenNoMatch() {
        model.mergeImportedRides([ride(offset: 4 * 3600)])
        #expect(model.finishRecording(result()) == .pending)
        #expect(model.pendingRecordings.count == 1)
    }

    @Test("Spätere FIT-Sekunden mit Leistung ersetzen die Puls-Spur, der Puls bleibt")
    func fitUpgradesHeartRateOnly() throws {
        model.mergeImportedRides([ride()])
        model.finishRecording(result())
        let fit = RideSeconds(power: [UInt16](repeating: 210, count: 1800), heartRate: nil)
        var incoming = ride(id: 5)
        incoming.powerCurve = [60: 210, 300: 210]
        model.mergeImportedRides([incoming], seconds: [5: fit])
        let seconds = try #require(model.rideSeconds(id: 77))
        #expect(seconds.power.allSatisfy { $0 == 210 })
        #expect(seconds.heartRate?.first == 130)
        #expect(model.recordingSource(for: ride()) == .measured)
    }

    @Test("Manueller Versatz verschiebt die Spur")
    func manualShift() throws {
        model.mergeImportedRides([ride()])
        var hr = [UInt8](repeating: 100, count: 1800)
        for i in 100..<200 { hr[i] = 150 }
        var r = result()
        r.seconds = RideSeconds(power: [UInt16](repeating: 0, count: 1800), heartRate: hr)
        model.finishRecording(r, manualShift: 30)
        let seconds = try #require(model.rideSeconds(id: 77))
        #expect(seconds.heartRate?[70] == 150)    // 100 - 30
        #expect(seconds.heartRate?[69] == 100)
    }

    @Test("Aufwärm-Check greift mit angehängter Pulsspur als angenommene ERG")
    func warmupAssumedERG() throws {
        let ref = model.profile.effectiveWarmupCheckWatts
        let segments = WarmupCheck.ensuringBlock(in: [.warmup(10, from: 0.5, to: 0.7), .steady(20, at: 0.7)],
                                                 refWatts: ref, ftp: model.profile.ftp)
        let def = WorkoutDefinition(title: "Aufwärmen", type: .endurance, summary: "", segments: segments)
        let workout = StoredWorkout(proposal: PlannedWorkoutProposal(date: t0, definition: def, rationale: ""), source: .manual, weekFocus: nil)
        container.mainContext.insert(workout)
        model.mergeImportedRides([ride(duration: 2400)])
        model.finishRecording(result(duration: 2400, bpm: 128, planned: workout.id))
        let check = try #require(model.warmupCheck(for: ride(duration: 2400)))
        #expect(check.source == .assumedERG)
        #expect(check.valid)
        #expect(check.hrMean == 128)
    }

    @Test("Nicht-Rad-Aufzeichnungen werden nicht an Fahrten gehängt")
    func nonRide() {
        model.mergeImportedRides([ride()])
        var r = result()
        r.kind = .strength
        #expect(model.finishRecording(r) == .notRide)
        #expect(model.rideSeconds(id: 77) == nil)
        #expect(model.pendingRecordings.isEmpty)
    }

    @Test("Zonen: Pulszonen sichtbar, Leistungszonen leer statt Z1")
    func zones() {
        let seconds = RideSeconds(power: [UInt16](repeating: 0, count: 600), heartRate: [UInt8](repeating: 120, count: 600))
        let z = ZoneTime.compute(seconds, ftp: 250, heartRate: HeartRateZones(maxHeartRate: 190, thresholdHeartRate: nil))
        #expect(!z.hasPower)
        #expect(z.power.allSatisfy { $0 == 0 })
        #expect(z.heartTotal == 600)
    }

    struct DiskFull: Error {}

    @Test("Speicherfehler beim Zuordnen: Ergebnis .failed, keine Zuordnung, nichts wartet (Datei bleibt beim Dienst)")
    func attachSaveFailureReportsAndKeepsRecording() throws {
        model.mergeImportedRides([ride()])
        model.saveOverride = { throw DiskFull() }
        #expect(model.finishRecording(result()) == .failed)
        #expect(model.banner?.isError == true)
        #expect(model.recordingSource(for: ride()) == nil)
        #expect(model.pendingRecordings.isEmpty)
        model.saveOverride = nil
        #expect(model.rideSeconds(id: 77)?.heartRate == nil)   // Änderung zurückgenommen
        // Nach dem Fehler klappt ein zweiter Versuch mit derselben Aufzeichnung.
        #expect(model.finishRecording(result()) == .attached(rideID: 77))
    }

    @Test("Speicherfehler bei der Krafteinheit: nil, Fehler-Banner, keine halbe Zeile")
    func strengthSaveFailure() throws {
        let rec = RecordingResult(kind: .strength, title: "Kraft", startedAt: t0, endedAt: t0.addingTimeInterval(600),
                                  seconds: RideSeconds(power: [UInt16](repeating: 0, count: 600), heartRate: [UInt8](repeating: 120, count: 600)))
        model.saveOverride = { throw DiskFull() }
        #expect(model.saveStrength(from: rec, draft: .otherSport("x", exertion: 5, legShare: .light, note: "")) == nil)
        #expect(model.banner?.isError == true)
        model.saveOverride = nil
        #expect(model.storedStrengthRows().isEmpty)
    }

    @Test("Wartende Aufzeichnungen liegen in einer Datei (nicht im Backup) und werden aus den Defaults übernommen")
    func pendingInFileWithMigration() throws {
        let legacy = StoredRecording(result())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        defaults.set(try encoder.encode([legacy]), forKey: AppModel.Keys.recordingPending)
        #expect(model.pendingRecordings.map(\.id) == [legacy.id])      // Migration beim ersten Lesen
        #expect(defaults.data(forKey: AppModel.Keys.recordingPending) == nil)
        #expect(FileManager.default.fileExists(atPath: model.pendingRecordingsURL.path))
        #expect(ProtectedFile.isExcludedFromBackup(model.pendingRecordingsURL))
        #expect(model.finishRecording(result(start: t0.addingTimeInterval(86_400))) == .pending)
        #expect(model.pendingRecordings.count == 2)
        #expect(defaults.data(forKey: AppModel.Keys.recordingPending) == nil)
    }
}
