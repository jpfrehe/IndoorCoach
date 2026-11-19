import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

/// Gesundheitsdateien in Application Support: nicht im iCloud-/Geräte-Backup (Resource-Value prüfbar auch auf macOS).
@Suite("Gesundheitsdateien nicht im Backup", .serialized)
@MainActor
struct ProtectedFileTests {
    func tempDir() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("pf-\(UUID().uuidString)", isDirectory: true) }

    @Test func helperWritesAtomicallyAndExcludesFromBackup() throws {
        let url = tempDir().appendingPathComponent("a.json")
        try ProtectedFile.write(Data("1".utf8), to: url)
        #expect(ProtectedFile.isExcludedFromBackup(url))
        // Ein zweites (atomares) Schreiben ersetzt die Datei und muss die Ausnahme erneut setzen.
        try ProtectedFile.write(Data("2".utf8), to: url)
        #expect(ProtectedFile.isExcludedFromBackup(url))
        #expect(try Data(contentsOf: url) == Data("2".utf8))
    }

    @Test func morningHRVFileIsExcluded() {
        let url = tempDir().appendingPathComponent("morning-hrv.json")
        let store = MorningHRVStore(url: url, defaults: UserDefaults(suiteName: "pf-\(UUID().uuidString)")!)
        store.save(MorningHRV.Measurement(day: Calendar.current.startOfDay(for: .now), lnRMSSD: 4, beats: 300, quality: 1, measuredAt: .now),
                   now: .now)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(ProtectedFile.isExcludedFromBackup(url))
    }

    @Test func recordingInterimFileIsExcluded() {
        let dir = tempDir()
        let store = RecordingStore(directory: dir)
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        store.save(StoredRecording(id: UUID(), kind: .ride, title: "x", startedAt: t, endedAt: t.addingTimeInterval(60),
                                   heartRate: Data([100, 101]), gapSeconds: 0, reconnects: 0, plannedWorkoutID: nil,
                                   definition: nil, strength: nil))
        #expect(ProtectedFile.isExcludedFromBackup(dir.appendingPathComponent(RecordingStore.fileName)))
    }

    @Test func wellnessCacheFileIsExcluded() async throws {
        let container = try AppEnvironment.makeContainer(inMemory: true)
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(),
                             defaults: UserDefaults(suiteName: "pf-\(UUID().uuidString)")!)
        let dir = tempDir()
        let day = Calendar.current.startOfDay(for: .now)
        model.healthSource = StubHealthDataSource(daily: [HealthDaily(date: day, metric: .restingHR, value: 55,
                                                                      source: HealthSourceRef(name: "Watch", bundleID: "com.apple.health"))])
        model.healthEnabled = true
        await model.refreshWellness(now: .now, directory: dir)
        let file = dir.appendingPathComponent(AppModel.wellnessCacheFile)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(ProtectedFile.isExcludedFromBackup(file))
        model.resetWellnessState()   // der Wellness-Zustand liegt in einer statischen Tabelle je Modell-Adresse
    }
}
