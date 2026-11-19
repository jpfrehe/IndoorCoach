import Foundation

/// Export eigener Einheiten nach Apple Health (docs/17 §8.4, B51): nach dem Speichern einer aufgezeichneten Kraft-/Andere-
/// Einheit und nach dem Anhängen einer Rad-Aufzeichnung. Je Sportart opt-in (Standard aus), nie Leistung, nichts bei
/// Überlappung mit dem Workout einer anderen Quelle (`HealthExportRules`). Der Export läuft im Hintergrund, blockiert den
/// Nutzer nie und protokolliert Fehler nur als Art (keine Werte).
extension AppModel {
    /// Service auf den Defaults und dem Schreibzugriff des Modells (dieselben wie in Profil → Datenquellen).
    public var healthExport: HealthExportService { HealthExportService(writer: healthWriter, defaults: defaults) }

    /// Reiht den Export ein, wenn die Sportart eingeschaltet ist. Gleiche IDs werden nie doppelt geschrieben.
    func exportToHealth(_ candidate: HealthExportCandidate) {
        let service = healthExport
        guard service.isAvailable, service.settings.isEnabled(candidate.sport) else { return }
        let previous = healthExportTask
        healthExportTask = Task { @MainActor [weak self] in
            await previous?.value
            await self?.runHealthExport(candidate, service: service)
        }
    }

    func exportToHealth(_ row: StoredStrengthSession) {
        guard row.source == .recorded, row.durationSeconds > 0 else { return }
        exportToHealth(HealthExportCandidate(
            id: row.id, sport: row.isOtherSport ? .other : .strength,
            activityTypeName: row.sportName.map { HealthImport.activityTypeName(forSport: $0) },
            start: row.start, end: row.start.addingTimeInterval(TimeInterval(row.durationSeconds)), heartRate: row.heartRateSeries))
    }

    func exportToHealth(_ recording: StoredRecording) {
        exportToHealth(HealthExportCandidate(id: recording.id, sport: .cycling, activityTypeName: nil, start: recording.startedAt,
                                             end: recording.endedAt, heartRate: recording.heartRateSeconds))
    }

    private func runHealthExport(_ candidate: HealthExportCandidate, service: HealthExportService) async {
        // Überlappungsprüfung gegen Workouts aller Quellen rund um die Einheit. Ist Health nicht lesbar, wird nichts
        // geschrieben: lieber kein Workout als ein doppeltes.
        let existing: [HealthWorkout]
        do {
            let low = candidate.start.addingTimeInterval(-86_400), high = candidate.end.addingTimeInterval(86_400)
            existing = try await healthSource.workouts(since: nil).added.filter { $0.end >= low && $0.start <= high }
        } catch {
            Log.error(.sync, "Health-Export ohne Überlappungsprüfung übersprungen: \(type(of: error))")
            return
        }
        let result = await service.export([candidate], existing: existing)
        if !result.failed.isEmpty {
            Log.error(.sync, "Health-Export fehlgeschlagen (\(candidate.sport.rawValue))")
        } else if !result.exported.isEmpty {
            Log.notice(.sync, "Health-Export: \(candidate.sport.rawValue) gespeichert")
        }
    }
}
