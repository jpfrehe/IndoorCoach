import Foundation
import SwiftData

extension AppModel {
    // MARK: - Ride import without Strava (MyWhoosh history, FIT files)

    /// Pull-to-refresh / app start: every connected source. `userInitiated` also reports "nothing new".
    public func syncRides(userInitiated: Bool = false) async {
        if isStravaConnected { await syncStrava() }
        if isMyWhooshConnected { await importMyWhooshRides(announce: userInitiated) }
        if userInitiated && !isStravaConnected && !isMyWhooshConnected {
            show("Keine Datenquelle verbunden – verbinde Strava oder MyWhoosh unter Profil → Dienste & Geräte oder importiere FIT-Dateien.", error: false)
        }
    }

    /// Stable negative id for rides that do not come from Strava (Strava ids are positive, so they never collide).
    static func importedRideID(_ key: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325                 // FNV-1a, stable across launches (unlike Hasher)
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
        return -Int(hash & 0x3FFF_FFFF_FFFF_FFFF) - 1
    }

    /// Loads past MyWhoosh rides (list + FIT file per ride). New rides only; the first import covers 210 days.
    public func importMyWhooshRides(full: Bool = false, announce: Bool = true) async {
        guard isMyWhooshConnected, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        let started = ContinuousClock.now
        let since = (!full ? lastMyWhooshImport?.addingTimeInterval(-7 * 86_400) : nil)
            ?? Calendar.current.date(byAdding: .day, value: -210, to: .now)!
        do {
            let list = try await myWhoosh.activities(notBefore: since)
            // Field names only (no values) – lets a diagnostics export show how MyWhoosh answers.
            Log.notice(.sync, "MyWhoosh-Fahrtenliste: \(list.activities.count) Einträge, Antwort-Felder \(list.responseKeys), Eintrags-Felder \(list.itemKeys)")
            let known = Set(((try? context.fetch(FetchDescriptor<StoredRide>())) ?? []).map(\.stravaID))
            let fresh = list.activities
                .filter { ($0.date ?? .now) >= since && !known.contains(Self.importedRideID("mywhoosh:\($0.id)")) }
                .prefix(80)
            var rides: [RideSummary] = []
            var unreadable = 0
            var fileAccess = true                       // after the first refused file, use the list values only
            for activity in fresh {
                if let ride = await myWhooshRide(activity, fileAccess: &fileAccess) { rides.append(ride) } else { unreadable += 1 }
            }
            let inserted = storeImportedRides(rides)
            // Only move the window forward when every listed ride made it in – otherwise retry them next time.
            if unreadable == 0 {
                lastMyWhooshImport = .now
                defaults.set(lastMyWhooshImport, forKey: Keys.myWhooshLastImport)
            }
            Log.notice(.sync, "MyWhoosh-Import: \(fresh.count) neu gelistet, \(inserted) gespeichert, \(unreadable) ohne Daten, \(Self.elapsed(since: started))")
            if announce && unreadable > 0 && inserted == 0 {
                syncErrors[.myWhoosh] = "\(unreadable) \(unreadable == 1 ? "Fahrt" : "Fahrten") ohne auswertbare Daten."
            } else {
                syncErrors[.myWhoosh] = nil
            }
            if inserted > 0 {
                show("MyWhoosh: \(inserted) \(inserted == 1 ? "Fahrt" : "Fahrten") importiert.", error: false)
            } else if unreadable > 0 {
                show("MyWhoosh liefert zu \(unreadable) Fahrten keine auswertbaren Daten. Importiere sie als FIT-Dateien (Profil → Dienste & Geräte → FIT-Dateien importieren).", error: true)
            } else if announce {
                show("MyWhoosh: keine neuen Fahrten.", error: false)
            }
        } catch {
            Log.error(.sync, "MyWhoosh-Import fehlgeschlagen: \(type(of: error)) – \(error.localizedDescription)")
            refreshCredentialState()
            // At app start a history that MyWhoosh refuses is only logged – the user saw it once already.
            if announce || error as? MyWhooshError != .historyUnavailable {
                syncErrors[.myWhoosh] = Self.myWhooshErrorText(error)
                show(error.localizedDescription, error: true)
            }
        }
    }

    /// Kurzer Text für die Verbindungszeile (der Banner trägt die lange Meldung).
    static func myWhooshErrorText(_ error: Error) -> String {
        switch error as? MyWhooshError {
        case .sessionExpired?, .notConnected?: "Anmeldung abgelaufen – bitte neu anmelden."
        case .historyUnavailable?: "Fahrtenliste nicht verfügbar – importiere FIT-Dateien."
        default: "Import fehlgeschlagen."
        }
    }

    /// One listed activity → ride: from its FIT file when available, otherwise from the list's own numbers.
    fileprivate func myWhooshRide(_ activity: MyWhooshActivity, fileAccess: inout Bool) async -> RideSummary? {
        let id = Self.importedRideID("mywhoosh:\(activity.id)")
        let name = activity.name ?? "MyWhoosh-Fahrt"
        if fileAccess, activity.fitURL != nil || activity.fileKey != nil {
            do {
                let fit = try FITParser.summary(from: try await myWhoosh.downloadFIT(for: activity))
                return RideSummary(fit: fit, id: id, name: name)
            } catch {
                fileAccess = false
                Log.error(.sync, "FIT-Datei von MyWhoosh nicht ladbar/lesbar: \(type(of: error)) – nutze für diesen Import die Werte der Liste")
            }
        }
        // Without the file: the list's own summary (duration, avg power, avg HR) – enough for TSS and Relative Effort.
        guard let date = activity.date, let seconds = activity.durationSeconds, seconds > 0 else {
            Log.error(.sync, "MyWhoosh-Fahrt ohne Datum/Dauer übersprungen (Datum \(activity.date != nil), Dauer \(activity.durationSeconds.map(String.init) ?? "–"))")
            return nil
        }
        return RideSummary(id: id, name: name, sportType: "VirtualRide", startDate: date, movingTime: seconds,
                           distance: activity.distanceMeters ?? 0, averageWatts: activity.averageWatts,
                           averageHeartrate: activity.averageHeartrate, trainer: true)
    }

    /// Imports FIT files picked in the Files app or opened via "Öffnen in IndoorCoach" (MyWhoosh, Zwift, Wahoo …).
    /// A file for a ride that is already stored (Strava, MyWhoosh list) adds its seconds data to that ride.
    public func importFITFiles(_ urls: [URL]) {
        var rides: [RideSummary] = []
        var seconds: [Int: RideSeconds] = [:]
        var failed = 0
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let fit = try? FITParser.summary(from: data) else { failed += 1; continue }
            let name = url.deletingPathExtension().lastPathComponent
            let id = Self.importedRideID("fit:\(Int(fit.startDate.timeIntervalSince1970))")
            rides.append(RideSummary(fit: fit, id: id, name: name.isEmpty ? "Indoor-Fahrt" : name))
            if let s = fit.seconds { seconds[id] = s }
        }
        let result = mergeImportedRides(rides, seconds: seconds)
        Log.notice(.sync, "FIT-Import: \(urls.count) Dateien, \(result.inserted) neu, \(result.enriched) ergänzt, \(failed) nicht lesbar")
        show(Self.fitImportMessage(result, failed: failed), error: failed > 0)
    }

    static func fitImportMessage(_ result: ImportResult, failed: Int) -> String {
        func rides(_ n: Int) -> String { n == 1 ? "Fahrt" : "Fahrten" }
        switch (result.inserted, result.enriched, failed) {
        case (0, 0, 0): return "Diese Fahrten sind schon in der App."
        case (let n, 0, 0): return "\(n) \(rides(n)) importiert."
        case (0, let e, 0): return "\(e) \(rides(e)) mit Sekundendaten ergänzt."
        case (0, 0, _): return "Die Datei ist keine lesbare FIT-Aktivität."
        default:
            var parts: [String] = []
            if result.inserted > 0 { parts.append("\(result.inserted) importiert") }
            if result.enriched > 0 { parts.append("\(result.enriched) ergänzt") }
            if failed > 0 { parts.append("\(failed) nicht lesbar") }
            return parts.joined(separator: ", ") + "."
        }
    }

    /// Outcome of an import: new rides, existing rides that received seconds data, rides skipped as duplicates.
    struct ImportResult: Equatable {
        var inserted = 0
        var enriched = 0
        var skipped = 0
        /// The newest ride that was inserted (for the "Neue Fahrt vom Mac" banner).
        var lastInserted: RideSummary?
    }

    /// Inserts new rides; a ride that already exists (same id, or a start within 5 minutes – the same ride via Strava,
    /// the MyWhoosh list or a FIT file) is enriched with the incoming seconds data when it has none yet (see
    /// `RideMerge`), otherwise skipped. Real rides end demo mode.
    @discardableResult
    func mergeImportedRides(_ rides: [RideSummary], seconds: [Int: RideSeconds] = [:]) -> ImportResult {
        var result = ImportResult()
        guard !rides.isEmpty else { return result }
        if (try? context.fetchCount(FetchDescriptor<StoredRide>(predicate: #Predicate { $0.isDemo }))) ?? 0 > 0 {
            deleteDemoData()
        }
        let stored = (try? context.fetch(FetchDescriptor<StoredRide>())) ?? []
        var byID = Dictionary(stored.map { ($0.stravaID, $0) }, uniquingKeysWith: { first, _ in first })
        var working = stored.map(\.summary)
        for ride in rides {
            switch RideMerge.decide(ride, existing: working) {
            case .insert:
                let row = StoredRide(ride)
                row.secondsData = seconds[ride.id]?.encoded()
                context.insert(row)
                byID[ride.id] = row
                working.append(ride)
                result.inserted += 1
                if result.lastInserted.map({ $0.startDate < ride.startDate }) ?? true { result.lastInserted = ride }
            case .enrich(let id):
                guard let index = working.firstIndex(where: { $0.id == id }) else { result.skipped += 1; continue }
                let merged = RideMerge.enriched(working[index], with: ride)
                working[index] = merged
                absorbHealthRide(byID[id], by: ride) // ANCHOR-W3B: ein Health-Workout geht in der echten Fahrt auf
                byID[id]?.update(from: merged)
                // ANCHOR-REC: seconds of a pulse-only recording are replaced by measured ones (pulse kept)
                if let s = seconds[ride.id], let row = byID[id], let upgraded = upgradedSeconds(s, over: row) { row.secondsData = upgraded.encoded() }
                result.enriched += 1
            case .alreadyComplete(let id):
                // Same ride with a curve but without stored seconds (imported before they were kept): add them.
                if let s = seconds[ride.id], let row = byID[id], row.secondsData == nil { row.secondsData = s.encoded() }
                result.skipped += 1
            case .duplicate:
                result.skipped += 1
            }
        }
        linkCompletedWorkouts()
        guard saveReportingErrors("Der Import") else { return ImportResult() }   // nichts davon ist gespeichert
        matchPendingRecordings() // ANCHOR-REC: recordings that waited for a ride
        invalidateSecondsDigests()
        hasImportedRides = true
        defaults.set(true, forKey: Keys.ridesImported)
        return result
    }

    /// The stored 1 Hz data of a ride (`StoredRide.stravaID`), nil without seconds data.
    public func rideSeconds(id: Int) -> RideSeconds? {
        var descriptor = FetchDescriptor<StoredRide>(predicate: #Predicate { $0.stravaID == id })
        descriptor.fetchLimit = 1
        return RideSeconds.decode((try? context.fetch(descriptor))?.first?.secondsData)
    }

    /// Inserts new rides, skipping ones already present (see `mergeImportedRides`). Returns the number inserted.
    @discardableResult
    func storeImportedRides(_ rides: [RideSummary]) -> Int {
        mergeImportedRides(rides).inserted
    }

    /// Marks past planned workouts as done when a ride exists on the same day.
    func linkCompletedWorkouts() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let workouts = try? context.fetch(FetchDescriptor<StoredWorkout>()),
              let rides = try? context.fetch(FetchDescriptor<StoredRide>()) else { return }
        for w in workouts where w.status == .planned && w.date <= today {
            // ANCHOR-W3B: Laufen/Wandern aus Health erfüllt keine Radeinheit.
            let sameDay = rides.filter { $0.foreignSport == nil && calendar.isDate($0.startDate, inSameDayAs: w.date) }
            if let ride = sameDay.first(where: { $0.summary.isIndoor }) ?? sameDay.first {
                w.status = .done
                w.linkedRideID = ride.stravaID
            }
        }
    }
}
