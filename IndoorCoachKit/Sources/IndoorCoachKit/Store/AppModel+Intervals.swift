import Foundation
import SwiftData

// intervals.icu (docs/19-PLAN-PLATTFORM-ANBINDUNGEN.md, Abschnitt 6): Pläne senden, Fahrten lesen.
extension AppModel {
    // MARK: - Verbinden und trennen

    /// OAuth mit PKCE über das übergebene Web-Auth (ASWebAuthenticationSession in der UI). Ohne Client-ID bleibt nur der API-Key.
    public func connectIntervals(authenticate: (URL) async throws -> URL) async {
        guard intervalsConfig.isOAuthAvailable else {
            show(IntervalsError.notConfigured.localizedDescription, error: true); return
        }
        let state = UUID().uuidString
        let verifier = IntervalsPKCE.makeVerifier()
        Log.notice(.intervals, "Verbinden gestartet")
        do {
            let url = intervalsConfig.authorizeURL(state: state, codeChallenge: IntervalsPKCE.challenge(for: verifier))
            let callback = try await authenticate(url)
            let credential = try await intervals.completeAuthorization(callbackURL: callback, expectedState: state, codeVerifier: verifier)
            await finishIntervalsConnect(name: credential.athleteName)
        } catch {
            Log.error(.intervals, "Verbinden fehlgeschlagen: \(type(of: error)) – \(error.localizedDescription)")
            show(error.localizedDescription, error: true)
        }
    }

    /// Übergangsweg: persönlicher API-Key des eigenen Kontos. Der Key wird zuerst geprüft und erst dann gespeichert.
    @discardableResult
    public func connectIntervals(apiKey: String) async -> Bool {
        Log.notice(.intervals, "Verbinden mit API-Key gestartet")
        do {
            let name = try await intervals.connect(apiKey: apiKey)
            defaults.set(name, forKey: Keys.intervalsAthleteName)
            await finishIntervalsConnect(name: name)
            return true
        } catch {
            Log.error(.intervals, "Verbinden fehlgeschlagen: \(type(of: error)) – \(error.localizedDescription)")
            show(error.localizedDescription, error: true)
            return false
        }
    }

    private func finishIntervalsConnect(name: String?) async {
        intervalsGeneration += 1
        syncErrors[.intervalsICU] = nil
        refreshCredentialState()
        Log.notice(.intervals, "Verbunden")
        show("Mit intervals.icu verbunden\(name.map { " (als \($0))" } ?? "").", error: false)
        // Läuft gerade eine andere Synchronisierung, erst auf deren Ende warten (höchstens ~30 s), sonst entfiele der Erstimport.
        for _ in 0..<300 where isSyncing { try? await Task.sleep(for: .milliseconds(100)) }
        await importIntervalsRides(full: true, announce: true)
        // Was schon geplant ist, soll gleich im intervals.icu-Kalender stehen.
        if profile.autoSendToIntervals {
            let today = Calendar.current.startOfDay(for: .now)
            let upcoming = ((try? context.fetch(FetchDescriptor<StoredWorkout>())) ?? [])
                .filter { $0.status == .planned && $0.date >= today && $0.intervalsSentAt == nil }
            await sendToIntervals(upcoming)
        }
    }

    /// Trennt (bei OAuth wird die Freigabe widerrufen, Best Effort). Importierte Fahrten bleiben, wie bei MyWhoosh.
    public func disconnectIntervals() async {
        intervalsGeneration += 1                  // laufende Importe und Sendungen verwerfen ihr Ergebnis
        pendingIntervalsSends = []
        await intervals.disconnect()
        Log.notice(.intervals, "Getrennt")
        intervalsNetworkDisabled = false
        lastIntervalsImport = nil
        defaults.removeObject(forKey: Keys.intervalsLastImport)
        defaults.removeObject(forKey: Keys.intervalsAthleteName)
        syncErrors[.intervalsICU] = nil
        for workout in (try? context.fetch(FetchDescriptor<StoredWorkout>())) ?? [] where workout.intervalsSentAt != nil {
            workout.intervalsSentAt = nil   // die Termine dort bleiben, aber die App kennt sie nicht mehr
        }
        saveReportingErrors("Das Trennen")
        refreshCredentialState()
        show("intervals.icu getrennt.", error: false)
    }

    // MARK: - Pläne senden

    /// Alle verbundenen Ziele, die für neue Pläne eingeschaltet sind (MyWhoosh, intervals.icu).
    func sendToPlanDestinations(_ workouts: [StoredWorkout]) async {
        if isMyWhooshConnected && profile.autoSendToMyWhoosh {
            await sendToMyWhoosh(workouts)
        }
        if isIntervalsConnected && profile.autoSendToIntervals {
            await sendToIntervals(workouts)
        }
    }

    /// Legt die Einheiten im intervals.icu-Kalender an oder ersetzt sie (ZWO-Datei, `external_id` = UUID der Einheit).
    /// intervals.icu reicht sie an Zwift, Garmin, Wahoo, Rouvy usw. weiter, falls dort verbunden.
    public func sendToIntervals(_ workouts: [StoredWorkout]) async {
        guard !workouts.isEmpty, isIntervalsConnected, !intervalsNetworkDisabled else { return }
        let ids = workouts.map(\.persistentModelID)
        if isSendingToIntervals {
            // Ein Senden läuft: diese Einheiten gehen gleich danach mit raus, statt verloren zu gehen.
            pendingIntervalsSends += ids.filter { !pendingIntervalsSends.contains($0) }
            return
        }
        isSendingToIntervals = true
        defer { isSendingToIntervals = false; try? context.save() }
        var batch = ids
        while !batch.isEmpty {
            await performIntervalsSend(batch)
            batch = pendingIntervalsSends
            pendingIntervalsSends = []
        }
    }

    private func performIntervalsSend(_ ids: [PersistentIdentifier]) async {
        let generation = intervalsGeneration
        var batch: [(id: PersistentIdentifier, payload: IntervalsPlannedWorkout)] = []
        for id in ids {
            guard let w = context.model(for: id) as? StoredWorkout, !w.isDeleted else { continue }
            let definition = w.definition
            batch.append((id, IntervalsPlannedWorkout(externalID: w.id.uuidString, name: w.title, start: startDate(for: w),
                                                      fileName: ZWOExporter.fileName(for: definition, date: w.date),
                                                      zwo: ZWOExporter.xml(for: definition), movingTime: definition.totalDuration)))
        }
        guard !batch.isEmpty else { return }
        do {
            try await intervals.upsertWorkouts(batch.map(\.payload))
            guard generation == intervalsGeneration else { return }   // zwischendurch getrennt
            for item in batch {
                if let w = context.model(for: item.id) as? StoredWorkout, !w.isDeleted { w.intervalsSentAt = .now }
            }
            syncErrors[.intervalsICU] = nil
            show("\(batch.count == 1 ? "Einheit" : "\(batch.count) Einheiten") an intervals.icu gesendet.", error: false)
        } catch {
            guard generation == intervalsGeneration else { return }
            Log.error(.intervals, "Senden fehlgeschlagen: \(type(of: error)) – \(error.localizedDescription)")
            refreshCredentialState()
            syncErrors[.intervalsICU] = Self.intervalsErrorText(error)
            show(error.localizedDescription, error: true)
        }
    }

    // MARK: - Fahrten importieren

    /// Lädt neue Fahrten aus intervals.icu (Liste, dann je Fahrt die FIT-Datei; ohne Datei zählen die Werte der Liste).
    /// Das Fenster reicht bis eine Woche vor den letzten Import, beim ersten Mal 210 Tage zurück. Eine Fahrt, die schon aus
    /// Strava, MyWhoosh oder einer FIT-Datei da ist, bekommt nur die Sekundendaten dazu (`mergeImportedRides`).
    public func importIntervalsRides(full: Bool = false, announce: Bool = true) async {
        guard isIntervalsConnected, !intervalsNetworkDisabled, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        let generation = intervalsGeneration
        let started = ContinuousClock.now
        let since = (!full ? lastIntervalsImport?.addingTimeInterval(-7 * 86_400) : nil)
            ?? Calendar.current.date(byAdding: .day, value: -210, to: .now)!
        do {
            let list = try await intervals.activities(oldest: since, newest: .now)
            guard generation == intervalsGeneration else { return }
            let known = Set(((try? context.fetch(FetchDescriptor<StoredRide>())) ?? []).map(\.stravaID))
            let skipped = Set(unreadableIntervalsActivities)
            let unknown = list.filter { !known.contains(Self.importedRideID("intervals:\($0.id)")) && !skipped.contains($0.id) }
            let fresh = unknown.prefix(Self.intervalsImportLimit)
            var rides: [RideSummary] = []
            var seconds: [Int: RideSeconds] = [:]
            var unreadable: [String] = []             // dauerhaft ohne Daten: wird gemerkt und blockiert das Fenster nicht
            var stopped: Error?                       // Zugang abgelaufen, Limit, Netz weg: den Rest beim nächsten Mal
            for activity in fresh {
                do {
                    if let (ride, secs) = try await intervalsRide(activity) {
                        rides.append(ride)
                        if let secs { seconds[ride.id] = secs }
                    } else { unreadable.append(activity.id) }
                } catch { stopped = error; break }
                guard generation == intervalsGeneration else { return }
            }
            guard generation == intervalsGeneration else { return }
            rememberUnreadableIntervalsActivities(unreadable)
            let failuresBefore = saveFailureCount
            let result = mergeImportedRides(rides, seconds: seconds)
            // Das Fenster rückt nur vor, wenn nichts Lesbares fehlt (Unlesbares ist gemerkt und zählt nicht mit).
            let complete = unknown.count <= Self.intervalsImportLimit && stopped == nil && saveFailureCount == failuresBefore
            if complete {
                lastIntervalsImport = .now
                defaults.set(lastIntervalsImport, forKey: Keys.intervalsLastImport)
            }
            Log.notice(.sync, "intervals.icu-Import: \(list.count) gelistet, \(unknown.count) neu, \(result.inserted) gespeichert, \(result.enriched) ergänzt, \(unreadable.count) ohne Daten, \(Self.elapsed(since: started))")
            if let stopped { throw stopped }
            if announce && !unreadable.isEmpty && result.inserted + result.enriched == 0 {
                syncErrors[.intervalsICU] = "\(unreadable.count) \(unreadable.count == 1 ? "Fahrt" : "Fahrten") ohne auswertbare Daten."
            } else {
                syncErrors[.intervalsICU] = nil
            }
            if result.inserted + result.enriched > 0 {
                show(Self.intervalsImportMessage(result), error: false)
            } else if !unreadable.isEmpty {
                show("intervals.icu liefert zu \(unreadable.count) Fahrten keine auswertbaren Daten. Importiere sie als FIT-Dateien (Profil → Dienste & Geräte → FIT-Dateien importieren).", error: true)
            } else if announce {
                show("intervals.icu: keine neuen Fahrten.", error: false)
            }
        } catch {
            guard generation == intervalsGeneration else { return }   // zwischendurch getrennt: kein Fehler mehr anzeigen
            Log.error(.sync, "intervals.icu-Import fehlgeschlagen: \(type(of: error)) – \(error.localizedDescription)")
            refreshCredentialState()
            syncErrors[.intervalsICU] = Self.intervalsErrorText(error)
            show(error.localizedDescription, error: true)
        }
    }

    /// Dauerhaft unlesbare Aktivitäten (Reihenfolge = Alter), höchstens `intervalsUnreadableLimit`.
    var unreadableIntervalsActivities: [String] { defaults.stringArray(forKey: Keys.intervalsUnreadable) ?? [] }
    static let intervalsUnreadableLimit = 500

    func rememberUnreadableIntervalsActivities(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        var all = unreadableIntervalsActivities
        all += ids.filter { !all.contains($0) }
        defaults.set(Array(all.suffix(Self.intervalsUnreadableLimit)), forKey: Keys.intervalsUnreadable)
    }

    /// Höchstens so viele neue Fahrten je Lauf (ein Download pro Fahrt).
    static let intervalsImportLimit = 80

    /// Eine gelistete Aktivität als Fahrt: aus der FIT-Datei (mit Sekundendaten), sonst aus den Werten der Liste.
    /// Wirft nur, wenn es nicht weitergehen soll (Zugang abgelaufen, Limit); jede andere Störung führt zum Rückfall auf die Liste.
    private func intervalsRide(_ activity: IntervalsActivity) async throws -> (RideSummary, RideSeconds?)? {
        let id = Self.importedRideID("intervals:\(activity.id)")
        let name = activity.name ?? "intervals.icu-Fahrt"
        do {
            let fit = try FITParser.summary(from: try await intervals.downloadFIT(activityID: activity.id))
            var ride = RideSummary(fit: fit, id: id, name: name)
            if let type = activity.type { ride.sportType = type }
            if let trainer = activity.trainer { ride.trainer = trainer }
            return (ride, fit.seconds)
        } catch let error as IntervalsError {
            switch error {
            // Vorübergehend oder Zugangsproblem: nicht mit den Listenwerten „abspeichern“, später richtig laden.
            case .notConnected, .forbidden, .rateLimited, .unavailable: throw error
            default: Log.error(.sync, "FIT-Datei von intervals.icu nicht ladbar: \(type(of: error)) – nutze die Werte der Liste")
            }
        } catch let error as URLError {
            throw error                                  // Zeitüberschreitung, offline …
        } catch {
            Log.error(.sync, "FIT-Datei von intervals.icu nicht lesbar: \(type(of: error)) – nutze die Werte der Liste")
        }
        return activity.rideSummary(id: id).map { ($0, nil) }
    }

    static func intervalsImportMessage(_ result: ImportResult) -> String {
        func rides(_ n: Int) -> String { n == 1 ? "Fahrt" : "Fahrten" }
        switch (result.inserted, result.enriched) {
        case (let n, 0): return "intervals.icu: \(n) \(rides(n)) importiert."
        case (0, let e): return "intervals.icu: \(e) \(rides(e)) mit Sekundendaten ergänzt."
        case (let n, let e): return "intervals.icu: \(n) \(rides(n)) importiert, \(e) mit Sekundendaten ergänzt."
        }
    }

    /// Kurzer Text für die Verbindungszeile (der Banner trägt die lange Meldung).
    static func intervalsErrorText(_ error: Error) -> String {
        switch error as? IntervalsError {
        case .notConnected?: "Zugang abgelaufen – bitte neu verbinden."
        case .rateLimited?: "intervals.icu-Limit erreicht – später erneut versuchen."
        case .forbidden?: "intervals.icu verweigert den Zugriff."
        case .keychainFailed?: "Zugang konnte nicht gespeichert werden."
        case .unavailable?: "intervals.icu ist gerade nicht erreichbar."
        default: error is URLError ? "intervals.icu ist gerade nicht erreichbar." : "Synchronisierung fehlgeschlagen."
        }
    }
}

#if DEBUG
extension AppModel {
    /// Launch argument `-uiIntervalsConnectedSeed YES` (nach `bootstrap()` aufrufen, siehe RootView): zeigt intervals.icu als
    /// verbunden, ohne Netzwerk. Der Zugang ist erfunden; Import und Senden sind in diesem Modus abgeschaltet.
    func applyIntervalsConnectedSeed() {
        guard UserDefaults.standard.bool(forKey: "uiIntervalsConnectedSeed") else { return }
        seedIntervalsConnected()
    }

    func seedIntervalsConnected() {
        intervalsStore.saveCredential(.apiKey("ui-test"))
        defaults.set("UI Test", forKey: Keys.intervalsAthleteName)
        intervalsNetworkDisabled = true
        syncErrors[.intervalsICU] = nil
        refreshCredentialState()
    }
}
#endif
