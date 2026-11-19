import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

/// Paket W3-I: Health-Import, Datenquellen, Aufzeichnung und Konstanz zusammengeführt.
@Suite("Integration Welle 3")
@MainActor
struct IntegrationW3Tests {
    static var keepAlive: [ModelContainer] = []
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func makeModel(source: FakeHealthSource = FakeHealthSource(), writer: StubHealthWorkoutWriter = StubHealthWorkoutWriter(),
                   defaults: UserDefaults? = nil) throws -> (AppModel, UserDefaults, StubHealthWorkoutWriter) {
        let container = try AppEnvironment.makeContainer(inMemory: true)
        Self.keepAlive.append(container)
        let defaults = defaults ?? UserDefaults(suiteName: "w3i-\(UUID().uuidString)")!
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults,
                             transport: RoutingTransport { _ in (200, Data("{}".utf8) ) })
        model.healthSource = source
        model.healthWriter = writer
        return (model, defaults, writer)
    }

    func recording(_ kind: RecordingKind = .strength, title: String = "Kraft", seconds: Int = 900, ago: TimeInterval = 7200) -> RecordingResult {
        let start = now.addingTimeInterval(-ago)
        return RecordingResult(kind: kind, title: title, startedAt: start, endedAt: start.addingTimeInterval(TimeInterval(seconds)),
                               seconds: RideSeconds(power: Array(repeating: 0, count: seconds),
                                                    heartRate: Array(repeating: 125, count: seconds)))
    }

    func foreign(start: TimeInterval, minutes: Double, name: String = "running") -> HealthWorkout {
        HealthWorkout(uuid: UUID(), start: now.addingTimeInterval(start), end: now.addingTimeInterval(start + minutes * 60),
                      activityTypeName: name, sourceName: "Apple Watch", sourceBundleID: "com.apple.health", isOwnSource: false,
                      avgHR: 140, maxHR: 160, energyKcal: nil)
    }

    // MARK: 1 · Datenquellen ↔ Health-Import

    @Test("Ein Health-Zustand: der Schalter der Datenquellen ist der des Imports, Einschalten gleicht sofort ab")
    func oneHealthStateAndImmediateSync() async throws {
        let source = FakeHealthSource([foreign(start: -7200, minutes: 40)])
        let (model, defaults, _) = try makeModel(source: source)
        let controller: any HealthSettingsControlling = model
        #expect(!controller.healthEnabled && controller.healthAvailable)
        await controller.setHealthEnabled(true)
        #expect(model.healthEnabled)
        #expect(source.workoutCalls >= 1, "sofortiger syncHealth()")
        #expect(((try? model.context.fetchCount(FetchDescriptor<StoredRide>())) ?? 0) > 0)
        #expect(defaults.bool(forKey: "health.enabled.v1"))
        #expect(defaults.object(forKey: "dataSources.healthEnabled.v1") == nil)
    }

    @Test("Migration: war einer der beiden alten Schalter an, ist Health an; alte Keys sind danach weg")
    func legacyToggleMigrates() throws {
        let defaults = UserDefaults(suiteName: "w3i-\(UUID().uuidString)")!
        defaults.set(true, forKey: "dataSources.healthEnabled.v1")
        var pins = HealthSourcePins()
        pins.pin(HealthSourceRef(name: "Apple Watch", bundleID: "com.apple.health"), for: .restingHR, from: nil)
        defaults.set(try JSONEncoder().encode(pins), forKey: "dataSources.pins.v1")
        let (model, _, _) = try makeModel(defaults: defaults)
        #expect(model.healthEnabled)
        #expect(model.pins.pins[.restingHR]?.source.name == "Apple Watch")
        #expect(defaults.object(forKey: "dataSources.healthEnabled.v1") == nil)
        #expect(defaults.object(forKey: "dataSources.pins.v1") == nil)
        let (again, _, _) = try makeModel(defaults: defaults)   // Neustart: bleibt an
        #expect(again.healthEnabled && again.pins.pins[.restingHR] != nil)
    }

    @Test("Der W3-B-Schalter allein genügt ebenfalls (kein Zurücksetzen durch die Migration)")
    func newToggleOnlyStaysOn() throws {
        let defaults = UserDefaults(suiteName: "w3i-\(UUID().uuidString)")!
        defaults.set(true, forKey: "health.enabled.v1")
        let (model, _, _) = try makeModel(defaults: defaults)
        #expect(model.healthEnabled)
    }

    @Test("Pins werden im AppModel gespeichert und überleben den Neustart")
    func pinsPersist() throws {
        let (model, defaults, _) = try makeModel()
        let garmin = HealthSourceRef(name: "Garmin Connect", bundleID: "com.garmin.connect")
        model.pin(garmin, for: .hrvSDNN)
        #expect(model.pins.pins[.hrvSDNN]?.source == garmin)
        let (again, _, _) = try makeModel(defaults: defaults)
        #expect(again.pins.pins[.hrvSDNN]?.source == garmin)
        again.pin(nil, for: .hrvSDNN)
        #expect(again.pins.pins[.hrvSDNN] == nil)
    }

    // MARK: 2 · Export nach dem Speichern

    @Test("Kraft: nur eingeschaltet, nie Leistung, Puls als Werte, genau einmal")
    func strengthExport() async throws {
        let (model, _, writer) = try makeModel()
        let draft = StrengthDraft(exertion: 6, legShare: .light)
        _ = model.saveStrength(from: recording(), draft: draft)
        await model.healthExportTask?.value
        #expect(writer.saved.isEmpty, "Standard aus")

        try await model.healthExport.setEnabled(.strength, true)
        let row = try #require(model.saveStrength(from: recording(ago: 3600), draft: draft))
        await model.healthExportTask?.value
        let saved = try #require(writer.saved.first)
        #expect(writer.saved.count == 1)
        #expect(saved.id == row.id)
        #expect(saved.activityTypeName == "traditionalStrengthTraining")
        #expect(saved.heartRate.count == 900 && saved.heartRate.allSatisfy { $0.bpm == 125 })
        #expect(saved.end.timeIntervalSince(saved.start) == 900)
    }

    @Test("Andere Einheit: Sportart wird auf den HealthKit-Namen abgebildet")
    func otherExport() async throws {
        let (model, _, writer) = try makeModel()
        try await model.healthExport.setEnabled(.other, true)
        _ = model.saveStrength(from: recording(.other, title: "Laufen"),
                               draft: .otherSport("Laufen", exertion: 5, legShare: nil, note: ""))
        await model.healthExportTask?.value
        #expect(writer.saved.first?.activityTypeName == "running")
        #expect(HealthImport.activityTypeName(forSport: "Schwimmen") == "swimming")
        #expect(HealthImport.activityTypeName(forSport: "climbing") == "climbing")
        #expect(HealthImport.activityTypeName(forSport: "Sonstiges") == "other")
    }

    @Test("Überlappung mit dem Workout einer anderen Quelle: nichts wird geschrieben")
    func overlapBlocksExport() async throws {
        let source = FakeHealthSource([foreign(start: -7200 + 60, minutes: 14)])
        let (model, _, writer) = try makeModel(source: source)
        try await model.healthExport.setEnabled(.strength, true)
        _ = model.saveStrength(from: recording(), draft: StrengthDraft(exertion: 6))
        await model.healthExportTask?.value
        #expect(writer.saved.isEmpty)
        // Befund 11: gezielte Abfrage mit Zeitfenster ±1 Tag, kein Lesen aller Workouts.
        #expect(source.workoutCalls == 0)
        let range = try #require(source.rangeRequests.first)
        #expect(range.lowerBound == now.addingTimeInterval(-7200 - 86_400))
        #expect(range.upperBound == now.addingTimeInterval(-7200 + 900 + 86_400))
    }

    @Test("Verbundene Quellen fragen die letzten 28 Tage gezielt ab, nicht alle Workouts")
    func connectedSourcesUsesTimeWindow() async throws {
        let recent = HealthWorkout(uuid: UUID(), start: Date.now.addingTimeInterval(-7200), end: Date.now.addingTimeInterval(-4800),
                                   activityTypeName: "running", sourceName: "Apple Watch", sourceBundleID: "com.apple.health",
                                   isOwnSource: false, avgHR: 140, maxHR: 160, energyKcal: nil)
        let source = FakeHealthSource([recent])
        let (model, _, _) = try makeModel(source: source)
        model.healthEnabled = true
        let usage = await model.connectedSources()
        #expect(source.workoutCalls == 0)
        let range = try #require(source.rangeRequests.first)
        #expect(source.rangeRequests.count == 1)
        #expect(range.upperBound.timeIntervalSince(range.lowerBound) >= 27 * 86_400 && range.upperBound.timeIntervalSince(range.lowerBound) <= 29 * 86_400)
        #expect(usage.contains { $0.metric == nil })   // Workouts-Quelle (Apple Watch) bleibt sichtbar
    }

    @Test("Ein Schreibfehler blockiert nicht und bricht nichts ab")
    func writerFailureIsSilent() async throws {
        let (model, _, writer) = try makeModel(writer: StubHealthWorkoutWriter(isAvailable: false))
        try? await model.healthExport.setEnabled(.strength, true)
        let row = model.saveStrength(from: recording(), draft: StrengthDraft(exertion: 6))
        await model.healthExportTask?.value
        #expect(row != nil)
        #expect(writer.saved.isEmpty)
    }

    @Test("Rad-Aufzeichnung: nach dem Anhängen an die Fahrt wird exportiert (nur Puls, nie Watt)")
    func cyclingExportAfterAttach() async throws {
        let (model, _, writer) = try makeModel()
        try await model.healthExport.setEnabled(.cycling, true)
        let start = now.addingTimeInterval(-3600)
        model.mergeImportedRides([RideSummary(id: 77, name: "MyWhoosh", sportType: "VirtualRide", startDate: start,
                                              movingTime: 1800, distance: 0, trainer: true)])
        let result = RecordingResult(kind: .ride, title: "SS", startedAt: start, endedAt: start.addingTimeInterval(1800),
                                     seconds: RideSeconds(power: Array(repeating: 0, count: 1800),
                                                          heartRate: Array(repeating: 130, count: 1800)))
        #expect(model.finishRecording(result) == .attached(rideID: 77))
        await model.healthExportTask?.value
        let saved = try #require(writer.saved.first)
        #expect(saved.activityTypeName == "cycling" && saved.id == result.id)
        #expect(saved.heartRate.count == 1800)
    }

    @Test("Rad-Aufzeichnung ohne passende Fahrt wartet und exportiert erst beim Anhängen")
    func pendingRecordingExportsLater() async throws {
        let (model, _, writer) = try makeModel()
        try await model.healthExport.setEnabled(.cycling, true)
        let start = now.addingTimeInterval(-3600)
        let result = RecordingResult(kind: .ride, title: "SS", startedAt: start, endedAt: start.addingTimeInterval(1800),
                                     seconds: RideSeconds(power: Array(repeating: 0, count: 1800),
                                                          heartRate: Array(repeating: 130, count: 1800)))
        #expect(model.finishRecording(result) == .pending)
        await model.healthExportTask?.value
        #expect(writer.saved.isEmpty)
        model.mergeImportedRides([RideSummary(id: 78, name: "MyWhoosh", sportType: "VirtualRide", startDate: start,
                                              movingTime: 1800, distance: 0, trainer: true)])
        await model.healthExportTask?.value
        #expect(writer.saved.count == 1)
    }

    // MARK: 3 · Alle Daten löschen

    @Test("Alle Daten löschen entfernt Gurt, Joker, Kraft-Vorlagen, Studio-Tage, Hinweise, Export und Health-Pins")
    func deleteAllRemovesNewKeys() async throws {
        let source = FakeHealthSource([foreign(start: -7200, minutes: 40)])
        let (model, defaults, _) = try makeModel(source: source)
        await model.setHealthEnabled(true)
        model.pin(HealthSourceRef(name: "Apple Watch", bundleID: "x"), for: .restingHR)
        try await model.healthExport.setEnabled(.strength, true)
        _ = model.saveStrength(from: recording(), draft: StrengthDraft(exertion: 6))
        await model.healthExportTask?.value
        model.saveStrengthTemplate(StrengthTemplate(name: "Push", exerciseIDs: ["squat"]))
        model.strengthDays = [2, 4]
        StrapStore(defaults: defaults).savedID = UUID()
        defaults.set([123.0], forKey: AppModel.manualJokerKey)
        defaults.set(["x"], forKey: AppModel.legLoadKeptKey)
        defaults.set(true, forKey: "strapExplainerSeen")
        defaults.set(Data([1]), forKey: "dataSources.pins.v1")

        await model.deleteAllData()

        for key in AppModel.Keys.all + AppModel.healthStateKeys + AppModel.uiFlagKeys {
            #expect(defaults.object(forKey: key) == nil, "\(key) noch gesetzt")
        }
        for type in HealthReadType.allCases { #expect(HealthAnchorStore(defaults: defaults).anchor(for: type) == nil) }
        #expect(model.pins.pins.isEmpty && !model.healthEnabled)
        #expect(model.strengthTemplates().isEmpty && model.strengthDays.isEmpty)
        #expect(model.healthExport.settings == HealthExportSettings())
    }

    // MARK: 4 · Verlauf Fremdsport

    @Test("Fremdsport: Symbol der Sportart, nie Rad; Outdoor-Filter nur für echte Radfahrten")
    func foreignSportSymbolAndFilter() {
        #expect(SportClassification.symbol(for: "running") == "figure.run")
        #expect(SportClassification.symbol(for: "swimming") == "figure.pool.swim")
        #expect(SportClassification.symbol(for: "Wandern") == "figure.hiking")
        #expect(SportClassification.symbol(for: "etwasUnbekanntes") == "figure.mixed.cardio")
        var run = RideSummary(id: 5, name: "Laufen", sportType: "Run", startDate: now, movingTime: 1800, distance: 0)
        run.foreignSport = "running"
        run.estimatedTSS = 40
        let ride = RideSummary(id: 6, name: "Runde", sportType: "Ride", startDate: now, movingTime: 1800, distance: 20_000)
        #expect(!RideFilter.outdoor.matches(run) && RideFilter.outdoor.matches(ride))
        #expect(!RideFilter.indoor.matches(run) && RideFilter.all.matches(run))
    }

    @Test("Der Zusammenführungs-Hinweis kommt bis in die Fahrtenliste")
    func healthNoteReachesTheSummary() throws {
        var r = RideSummary(id: -9, name: "X", sportType: "VirtualRide", startDate: now, movingTime: 600, distance: 0, trainer: true)
        r.healthNote = "Mit Health zusammengeführt."
        let row = StoredRide(r)
        row.healthNote = "Mit Health zusammengeführt."
        #expect(row.summary.healthNote == "Mit Health zusammengeführt.")
    }

    // MARK: 5 · Gewicht

    @Test("Health-Gewicht kommt in W/kg und VO₂max an; das manuelle bleibt Rückfall")
    func healthWeightReachesWattsPerKg() async throws {
        let source = FakeHealthSource([], weight: 80)
        let (model, _, _) = try makeModel(source: source)
        model.profile.weightKg = 70
        model.profile.ftp = 240
        let manual = model.calculationProfile.wattsPerKg
        #expect(abs(manual - 240.0 / 70) < 0.001)
        let curve = PowerCurve.Aggregate(points: [300: PowerCurve.Point(duration: 300, watts: 300, source: .measured, rideID: 1, date: now)], totalRides: 1, measuredRides: 1)
        let before = try #require(VO2max.estimate(curve: curve, profile: model.calculationProfile)).value

        await model.setHealthEnabled(true)
        #expect(model.effectiveWeightKg == 80)
        #expect(abs(model.calculationProfile.wattsPerKg - 240.0 / 80) < 0.001)
        let after = try #require(VO2max.estimate(curve: curve, profile: model.calculationProfile)).value
        #expect(after < before, "mehr Gewicht → weniger W/kg → niedrigere VO₂max")
        #expect(model.profile.weightKg == 70, "das manuelle Gewicht wird nicht überschrieben")
    }

    // MARK: 6 · Konstanz

    @Test("Konstanz: eigener Text für die aktive Woche")
    func consistencySessionsLabel() {
        let text = ConsistencyCard.description(.fulfilled(.sessions))
        #expect(text.contains("Aktive Woche: Rad, Kraft & mehr"))
        #expect(ConsistencyCard.description(.fulfilled(.budget)) != text)
    }

    // MARK: 7 · Unterbrochene Kraft-Aufzeichnung

    @Test("Häkchen und Vorlagenname überleben den Abbruch und kommen beim Fortsetzen zurück")
    func strengthStateSurvivesInterruption() throws {
        let clock = TestClock(now)
        let store = RecordingStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("w3i-\(UUID().uuidString)"))
        let first = RecordingService(strap: nil, now: { clock.date }, store: store, presenter: { NoopRecordingLivePresenter() }, autoTick: false)
        first.start(kind: .strength, title: "Kraft")
        let state = StoredStrengthState(templateName: "Push", exercises: [
            PerformedExercise(exerciseID: "squat", sets: 3, reps: 8, weightKg: 80, checked: true),
            PerformedExercise(exerciseID: "bench_press", checked: false)])
        clock.advance(5)
        first.updateStrength(state)   // sofort gesichert, ohne auf die 30 s zu warten
        let second = RecordingService(strap: nil, now: { clock.date }, store: store, presenter: { NoopRecordingLivePresenter() }, autoTick: false)
        #expect(second.interrupted?.strength == state)
        let request = RecordingRequest.resumed(kind: .strength, title: "Kraft", restored: second.interrupted?.strength)
        #expect(request.restored?.templateName == "Push")
        second.resumeInterrupted()
        #expect(second.strength == state)
        let result = try #require(second.stop())
        second.confirmHandled(result)   // erst nach erfolgreichem Speichern fällt die Zwischendatei
        #expect(store.load() == nil)
    }

    @Test("Ältere Zwischendateien ohne Kraft-Zustand bleiben lesbar")
    func oldInterimFileDecodes() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"strength","title":"Kraft","startedAt":"2026-11-19T10:00:00Z","endedAt":"2026-11-19T10:10:00Z","heartRate":"AAA=","gapSeconds":0,"reconnects":0}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let stored = try decoder.decode(StoredRecording.self, from: Data(json.utf8))
        #expect(stored.strength == nil)
    }

    // MARK: 8 · Kraft-Detail

    @Test("Wird eine Krafteinheit mit einem Health-Workout zusammengeführt, trägt sie den Hinweis; er verschwindet mit dem Workout")
    func strengthMergeNote() async throws {
        let health = HealthWorkout(uuid: UUID(), start: now.addingTimeInterval(-7200 + 120), end: now.addingTimeInterval(-7200 + 120 + 3000),
                                   activityTypeName: "traditionalStrengthTraining", sourceName: "Hevy", sourceBundleID: "com.hevy",
                                   isOwnSource: false, avgHR: 120, maxHR: 140, energyKcal: nil)
        let source = FakeHealthSource([health])
        let (model, _, _) = try makeModel(source: source)
        let own = try #require(model.saveStrengthManual(start: now.addingTimeInterval(-7200), durationMinutes: 52, exertion: 6,
                                                       legShare: .light, exercises: []))
        #expect(own.healthNote == nil)
        await model.setHealthEnabled(true)
        let note = try #require(own.healthNote)
        #expect(note.contains("zusammengeführt") && note.contains("Hevy"))
        source.delete(health.uuid)
        await model.syncHealth(now: now)
        #expect(own.healthNote == nil)
    }
}
