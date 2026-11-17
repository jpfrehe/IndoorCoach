import Foundation
import SwiftData

/// Diagnostics export for the pilot (B05): header with app/device/profile facts plus this process's log
/// entries, fully redacted. Contains no free text from the profile (goal, notes, name) and no ride names.
extension AppModel {
    static let diagnosticsDirectory = "diagnostics"

    public func diagnosticsReport(since: Date = .now.addingTimeInterval(-24 * 3600)) async -> String {
        await diagnosticsReport(since: since) { try Log.storedEntries(since: $0) }
    }

    /// `entries` is injectable for tests; it runs off the main actor because reading the log store is slow.
    func diagnosticsReport(since: Date, entries: @escaping @Sendable (Date) throws -> [String]) async -> String {
        let header = diagnosticsHeader(since: since)
        let known = knownSecrets()
        let logLines: [String]
        do {
            logLines = try await Task.detached(priority: .utility) { try entries(since) }.value
        } catch {
            logLines = ["(Protokoll nicht verfügbar: \(type(of: error)))"]
        }
        let body = logLines.isEmpty ? "(keine Einträge)" : logLines.joined(separator: "\n")
        let report = header + "\n\n== Protokoll ==\n" + body + "\n"
        return Redactor.scrub(report, knownSecrets: known)
    }

    /// Writes the report into a temporary `.txt` for the share sheet.
    public func diagnosticsFile() async throws -> URL {
        let report = await diagnosticsReport()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(Self.diagnosticsDirectory, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.omitted).time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let url = dir.appendingPathComponent("IndoorCoach-Diagnose-\(stamp).txt")
        try report.write(to: url, atomically: true, encoding: .utf8)
        Log.notice(.app, "Diagnose exportiert (\(report.utf8.count) Bytes)")
        return url
    }

    func diagnosticsHeader(since: Date, now: Date = .now) -> String {
        let rides = (try? context.fetch(FetchDescriptor<StoredRide>())) ?? []
        let workouts = (try? context.fetch(FetchDescriptor<StoredWorkout>())) ?? []
        let p = profile
        let iso = ISO8601DateFormatter()
        func yesNo(_ b: Bool) -> String { b ? "ja" : "nein" }
        let days = p.trainingDays.compactMap { AthleteProfile.weekdayNames[$0] }.joined(separator: ",")
        return """
        IndoorCoach – Diagnose
        Erstellt: \(iso.string(from: now))
        Zeitraum: ab \(iso.string(from: since))

        == App & Gerät ==
        App-Version: \(AppConfig.versionString)
        Betriebssystem: \(AppConfig.osVersionString)
        Gerät: \(AppConfig.deviceModel)
        Sprache: \(Locale.current.identifier)

        == Verbindungen ==
        Strava verbunden: \(yesNo(isStravaConnected))
        Strava Client-ID eingetragen: \(yesNo(!stravaClientID.isEmpty))
        Strava Client-Secret hinterlegt: \(yesNo(hasStravaSecret))
        Claude-Key hinterlegt: \(yesNo(hasClaudeKey))
        Demo-Modus: \(yesNo(isDemoMode))
        Letzter Sync: \(lastSync.map { iso.string(from: $0) } ?? "–")

        == Profil (ohne Freitext) ==
        FTP: \(p.ftp) W
        Schwellen-HF gesetzt: \(yesNo(p.thresholdHeartRate != nil)), Max-HF gesetzt: \(yesNo(p.maxHeartRate != nil))
        Trainingstage: \(days) (\(p.trainingDays.count))
        Wochenbudget: \(Formatters.decimal(p.weeklyHours, digits: 1)) h, max. Einheit: \(p.longestSessionMinutes) min
        Planungshorizont: \(p.planHorizonDays) Tage, Modell: \(p.model)
        Zieldatum gesetzt: \(yesNo(p.goalDate != nil)), Saisonstart gesetzt: \(yesNo(p.arcStart != nil)), Ziel-Fitness gesetzt: \(yesNo(p.targetCTL != nil))

        == Daten ==
        Fahrten: \(rides.count) (Strava \(rides.filter { !$0.isDemo }.count), Demo \(rides.filter(\.isDemo).count))
        Einheiten: \(workouts.count) (geplant \(workouts.filter { $0.status == .planned }.count), erledigt \(workouts.filter { $0.status == .done }.count), im Kalender \(workouts.filter { $0.calendarEventID != nil }.count))
        """
    }

    /// Literal values that must never leave the device, replaced in addition to the pattern rules.
    private func knownSecrets() -> [String] {
        let tokens = secrets.tokenStore.loadTokens()
        return [secrets.secret(.claudeAPIKey), secrets.secret(.stravaClientSecret),
                tokens?.accessToken, tokens?.refreshToken, stravaAthleteName,
                profile.goal, profile.notes, profile.name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
