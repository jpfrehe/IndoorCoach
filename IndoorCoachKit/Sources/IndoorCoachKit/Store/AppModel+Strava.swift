import Foundation
import SwiftData

extension AppModel {
    // MARK: - Strava

    /// Runs OAuth via the provided web-auth closure (ASWebAuthenticationSession in the UI layer).
    public func connectStrava(authenticate: (URL) async throws -> URL) async {
        let config = stravaConfig
        guard config.isComplete else {
            show(StravaError.notConfigured.localizedDescription, error: true); return
        }
        let state = UUID().uuidString
        Log.notice(.strava, "Verbinden gestartet")
        do {
            let callback = try await authenticate(config.authorizeURL(state: state))
            let tokens = try await stravaClient.completeAuthorization(callbackURL: callback, expectedState: state)
            Log.notice(.strava, "Verbunden")
            refreshCredentialState()
            show("Mit Strava verbunden\(tokens.athleteName.map { " als \($0)" } ?? "").", error: false)
            resetDemoData()
            await syncStrava(full: true)
        } catch {
            Log.error(.strava, "Verbinden fehlgeschlagen: \(type(of: error)) – \(error.localizedDescription)")
            show(error.localizedDescription, error: true)
        }
    }

    public func disconnectStrava() async {
        await stravaClient.disconnect()
        Log.notice(.strava, "Getrennt")
        // Only Strava's rides go; rides imported from MyWhoosh or FIT files (negative ids) stay.
        try? context.delete(model: StoredRide.self, where: #Predicate { $0.stravaID > 0 })
        try? context.save()
        defaults.removeObject(forKey: Keys.lastSync)
        lastSync = nil
        syncErrors[.strava] = nil
        refreshCredentialState()
        bootstrap()
        show(isDemoMode ? "Strava getrennt – Demo-Daten aktiv." : "Strava getrennt.", error: false)
    }

    /// Incremental sync (overlap of 2 days to catch edits); full sync loads 120 days.
    public func syncStrava(full: Bool = false) async {
        guard isStravaConnected, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        let since: Date
        if !full, let lastSync {
            since = lastSync.addingTimeInterval(-7 * 86_400) // late uploads; upsert makes overlap cheap
        } else {
            // 210 days so the 42-day fitness average is warmed up before the visible 90-day window.
            since = Calendar.current.date(byAdding: .day, value: -210, to: .now)!
        }
        let started = ContinuousClock.now
        let windowDays = Int((Date.now.timeIntervalSince(since) / 86_400).rounded())
        Log.notice(.sync, "Sync gestartet: \(full ? "voll" : "inkrementell"), \(windowDays) Tage")
        do {
            let rides = try await stravaClient.fetchRides(after: since)
            // Leftover demo data (e.g. tokens restored without the connect flow) goes with the first real sync.
            if try context.fetchCount(FetchDescriptor<StoredRide>(predicate: #Predicate { $0.isDemo })) > 0 {
                deleteDemoData()
            }
            let existing = try context.fetch(FetchDescriptor<StoredRide>())
            var byID = Dictionary(existing.map { ($0.stravaID, $0) }, uniquingKeysWith: { first, _ in first })
            var inserted = 0
            for ride in rides {
                if let stored = byID[ride.id] { stored.update(from: ride) }
                else {
                    let stored = StoredRide(ride)
                    context.insert(stored)
                    byID[ride.id] = stored
                    inserted += 1
                }
            }
            linkCompletedWorkouts()
            try context.save()
            Log.notice(.sync, "Sync beendet: \(rides.count) Fahrten geladen, \(inserted) neu, \(rides.count - inserted) aktualisiert, \(byID.count) gesamt, \(Self.elapsed(since: started))")
            lastSync = .now
            defaults.set(lastSync, forKey: Keys.lastSync)
            syncErrors[.strava] = nil
            show(rides.isEmpty ? "Strava: keine neuen Fahrten." : "Strava: \(rides.count) Fahrten synchronisiert.", error: false)
        } catch {
            Log.error(.sync, "Sync fehlgeschlagen nach \(Self.elapsed(since: started)): \(type(of: error)) – \(error.localizedDescription)")
            refreshCredentialState()
            syncErrors[.strava] = Self.stravaErrorText(error)
            show(error.localizedDescription, error: true)
        }
    }

    /// Kurzer Text für die Verbindungszeile (der Banner trägt die lange Meldung).
    static func stravaErrorText(_ error: Error) -> String {
        switch error as? StravaError {
        case .notConnected?: "Zugang abgelaufen – bitte neu verbinden."
        case .rateLimited?: "Strava-Limit erreicht – später erneut versuchen."
        case .unavailable?: "Strava ist gerade nicht erreichbar."
        default: "Synchronisierung fehlgeschlagen."
        }
    }
}
