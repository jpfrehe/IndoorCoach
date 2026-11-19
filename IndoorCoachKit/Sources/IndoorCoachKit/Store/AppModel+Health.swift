import Foundation
import SwiftData

/// Workouts aus Apple Health im Store (docs/17 §2.3, §8.2, B47, B48, Gewicht aus B50).
///
/// Ablauf von `syncHealth()`: inkrementell über den Anker neue und gelöschte Workouts holen, jedes Neue mit
/// `HealthImport.decide` einordnen (eigene Quelle weg · Überlappung ≥ 50 % → zusammenführen · Rad → Fahrt · aerob →
/// Fahrt mit geschätzter TSS · Kraft → offener Kandidat) und das Ergebnis im Protokoll (`HealthLedgerEntry`) merken.
/// Es wird nichts nach Health geschrieben; Gesundheitswerte werden nie geloggt (nur Zähler).
extension AppModel {
    enum HealthKeys {
        static let enabled = "health.enabled.v1"
        static let ledger = "health.ledger.v1"
        static let weight = "health.weightKg.v1"
        static let pins = "health.pins.v1"
        /// Frühere Schalter/Pins der Datenquellen-Ansicht (vor der Zusammenführung); werden beim Laden übernommen und entfernt.
        static let legacyEnabled = "dataSources.healthEnabled.v1"
        static let legacyPins = "dataSources.pins.v1"
    }

    /// Die UserDefaults-Schlüssel des Health-Zustands; `resetHealthState()` räumt sie auf (nicht in `Keys.all`, damit der
    /// Anker zusammen mit ihnen fällt). Die Anker liegen im `HealthAnchorStore`, den Export-Zustand räumt `Keys.all`.
    static let healthStateKeys = [HealthKeys.enabled, HealthKeys.ledger, HealthKeys.weight, HealthKeys.pins,
                                  HealthKeys.legacyEnabled, HealthKeys.legacyPins]

    /// Ältere Workouts werden beim ersten Abgleich nicht übernommen (wie der Strava-Import: 120 bis 210 Tage).
    static let healthImportWindowDays = 210

    // MARK: Zustand

    func loadHealthState() {
        migrateLegacyHealthSettings()
        healthEnabled = defaults.bool(forKey: HealthKeys.enabled)
        healthPins = defaults.data(forKey: HealthKeys.pins).flatMap { try? JSONDecoder().decode(HealthSourcePins.self, from: $0) }
            ?? HealthSourcePins()
        healthWeightKg = defaults.object(forKey: HealthKeys.weight) as? Double
        healthCandidates = Self.candidates(in: loadHealthLedger())
    }

    /// Früher hatte die Datenquellen-Ansicht einen eigenen Schalter und eigene Pins. Ein eingeschalteter alter Schalter gilt
    /// weiter (an), die Pins werden übernommen; danach gibt es nur noch den einen Zustand.
    private func migrateLegacyHealthSettings() {
        if defaults.bool(forKey: HealthKeys.legacyEnabled) { defaults.set(true, forKey: HealthKeys.enabled) }
        if defaults.data(forKey: HealthKeys.pins) == nil, let old = defaults.data(forKey: HealthKeys.legacyPins) {
            defaults.set(old, forKey: HealthKeys.pins)
        }
        defaults.removeObject(forKey: HealthKeys.legacyEnabled)
        defaults.removeObject(forKey: HealthKeys.legacyPins)
    }

    func resetHealthState() {
        healthEnabled = false
        healthCandidates = []
        healthWeightKg = nil
        healthPins = HealthSourcePins()
        healthObserverStarted = false
        let anchors = HealthAnchorStore(defaults: defaults)
        for type in HealthReadType.allCases { anchors.save(nil, for: type) }
        for key in Self.healthStateKeys { defaults.removeObject(forKey: key) }
    }

    func loadHealthLedger() -> [HealthLedgerEntry] {
        defaults.data(forKey: HealthKeys.ledger).flatMap { try? JSONDecoder().decode([HealthLedgerEntry].self, from: $0) } ?? []
    }

    func saveHealthLedger(_ ledger: [HealthLedgerEntry]) {
        if ledger.isEmpty { defaults.removeObject(forKey: HealthKeys.ledger) }
        else if let data = try? JSONEncoder().encode(ledger) { defaults.set(data, forKey: HealthKeys.ledger) }
        healthCandidates = Self.candidates(in: ledger)
    }

    private static func candidates(in ledger: [HealthLedgerEntry]) -> [HealthLedgerEntry] {
        ledger.filter { $0.outcome == .candidate }.sorted { $0.start > $1.start }
    }

    // MARK: Aktivieren

    /// Schaltet Health als Datenquelle ein oder aus. Einschalten fragt die Leseberechtigung an (Workouts, Puls,
    /// Gewicht), meldet den Beobachter für neue Workouts an und gleicht sofort ab. Ausschalten löscht nichts; das
    /// manuelle Gewicht gilt dann wieder.
    public func setHealthEnabled(_ enabled: Bool) async {
        guard enabled else {
            healthEnabled = false
            defaults.set(false, forKey: HealthKeys.enabled)
            return
        }
        guard healthSource.isAvailable else {
            show("Apple Health ist auf diesem Gerät nicht verfügbar.", error: false)
            return
        }
        do {
            try await healthSource.requestReadAuthorization([.workouts, .heartRate, .bodyMass])
        } catch {
            Log.error(.app, "Health-Berechtigung fehlgeschlagen: \(type(of: error))")
            show("Apple Health konnte nicht aktiviert werden.", error: true)
            return
        }
        healthEnabled = true
        defaults.set(true, forKey: HealthKeys.enabled)
        await syncHealth()
    }

    // MARK: Datenquellen-Ansicht (HealthSettingsControlling)

    public var healthAvailable: Bool { healthSource.isAvailable }

    public func requestAuthorization() async throws {
        try await healthSource.requestReadAuthorization(Set(HealthReadType.allCases))
    }

    public var pins: HealthSourcePins { healthPins }

    /// Quellen der letzten 4 Wochen je Kennzahl (nil = Workouts); leer, solange Health aus ist.
    public func connectedSources() async -> [HealthSourceUsage] {
        guard healthEnabled, healthSource.isAvailable else { return [] }
        let now = Date.now
        let from = Calendar.current.date(byAdding: .day, value: -28, to: now) ?? now
        var dailies: [HealthDaily] = []
        for metric in HealthMetric.allCases {
            dailies += (try? await healthSource.dailyValues(metric, in: from...now)) ?? []
        }
        let workouts = (try? await healthSource.workouts(in: from...now)) ?? []
        return HealthSourceUsageBuilder.usage(dailies: dailies, workouts: workouts, now: now)
    }

    /// `nil` = automatisch (Pin lösen). Ein Wechsel startet eine neue Basis ab heute.
    public func pin(_ new: HealthSourceRef?, for metric: HealthMetric) {
        if let new {
            healthPins.pin(new, for: metric, from: healthPins.pins[metric] == nil ? nil : Calendar.current.startOfDay(for: .now))
        } else {
            healthPins.unpin(metric)
        }
        if let data = try? JSONEncoder().encode(healthPins) { defaults.set(data, forKey: HealthKeys.pins) }
    }

    // MARK: Gewicht

    /// Gewicht für Berechnungen (W/kg, VO₂max …): das 7-Tage-Mittel aus Health, wenn aktiviert und plausibel, sonst das
    /// manuelle. Bewusst berechnet statt das Profil zu überschreiben – das manuelle Gewicht bleibt der Rückfall und geht
    /// beim Ausschalten oder ohne Messwerte nicht verloren.
    public var effectiveWeightKg: Double {
        guard healthEnabled, let kg = healthWeightKg, Self.plausibleWeight.contains(kg) else { return profile.weightKg }
        return kg
    }

    /// Das Profil mit dem effektiven Gewicht – für Funktionen, die ein `AthleteProfile` erwarten (z. B. `VO2max`).
    public var calculationProfile: AthleteProfile {
        var p = profile
        p.weightKg = effectiveWeightKg
        return p
    }

    static let plausibleWeight = 30.0...250.0

    // MARK: Abgleich

    /// Holt neue und gelöschte Workouts seit dem letzten Anker und ordnet sie ein. Nur mit aktiviertem Health; läuft
    /// nie doppelt (ein Aufruf während eines Laufs löst genau einen weiteren aus). Fehler werden still protokolliert.
    @discardableResult
    public func syncHealth(now: Date = .now) async -> HealthSyncResult {
        var total = HealthSyncResult()
        guard healthEnabled, healthSource.isAvailable else { return total }
        if healthSyncing { healthSyncPending = true; return total }
        healthSyncing = true
        defer { healthSyncing = false }
        await startHealthObserver()
        repeat {
            healthSyncPending = false
            let step = await syncHealthOnce(now: now)
            total.imported += step.imported
            total.merged += step.merged
            total.candidates += step.candidates
            total.removed += step.removed
        } while healthSyncPending
        return total
    }

    private func startHealthObserver() async {
        guard !healthObserverStarted else { return }
        healthObserverStarted = true
        do {
            try await healthSource.enableBackgroundDeliveryForWorkouts { [weak self] in
                Task { @MainActor in await self?.syncHealth() }
            }
        } catch {
            Log.error(.sync, "Health-Beobachter nicht angemeldet: \(type(of: error))")
        }
    }

    private func syncHealthOnce(now: Date) async -> HealthSyncResult {
        var result = HealthSyncResult()
        let anchors = HealthAnchorStore(defaults: defaults)
        let changes: HealthWorkoutChanges
        do {
            changes = try await healthSource.workouts(since: anchors.anchor(for: .workouts))
        } catch {
            Log.error(.sync, "Health-Workouts nicht lesbar: \(type(of: error))")
            return result
        }
        let failuresBefore = saveFailureCount
        var ledger = loadHealthLedger()
        for uuid in changes.deleted where removeHealthWorkout(uuid, from: &ledger) { result.removed += 1 }

        let cutoff = now.addingTimeInterval(-Double(Self.healthImportWindowDays) * 86_400)
        let known = Set(ledger.map(\.uuid))
        let fresh = changes.added.filter { !known.contains($0.uuid) && $0.end >= cutoff }.sorted { $0.start < $1.start }
        if !fresh.isEmpty {
            var occupied = healthOccupied(around: fresh)
            for workout in fresh {
                let decision = HealthImport.decide(workout, occupied: occupied, thresholdHeartRate: profile.thresholdHeartRate,
                                                   heartRate: profile.heartRateProfile)
                switch decision {
                case .skip:
                    break
                case .merge(let kind, let supply):
                    if await mergeHealthWorkout(workout, into: kind, supplyHeartRate: supply, ledger: &ledger) {
                        result.merged += 1
                    } else {
                        // Ziel nicht mehr da: das Workout wird eine eigene Einheit statt still zu verschwinden.
                        let own = importAsOwn(workout, ledger: &ledger)
                        result.imported += own.imported
                        result.candidates += own.candidates
                        occupied.append(Self.occupied(for: workout))
                    }
                case .aerobic(let estimate):
                    if importHealthRide(workout, estimate: estimate, ledger: &ledger) { result.imported += 1 }
                    occupied.append(Self.occupied(for: workout))
                case .cycling:
                    if importHealthRide(workout, estimate: nil, ledger: &ledger) { result.imported += 1 }
                    occupied.append(Self.occupied(for: workout))
                case .candidate:
                    ledger.append(HealthLedgerEntry(workout, outcome: .candidate))
                    result.candidates += 1
                }
            }
        }
        // Anker und Protokoll rücken nur nach erfolgreichem Speichern vor; sonst kommt dieselbe Änderung beim nächsten Abgleich erneut.
        guard saveReportingErrors("Der Health-Abgleich"), saveFailureCount == failuresBefore else { return HealthSyncResult() }
        anchors.save(changes.anchor, for: .workouts)
        await refreshHealthWeight(now: now)
        saveHealthLedger(Self.pruned(ledger, now: now))
        if result.imported + result.merged + result.candidates + result.removed > 0 {
            Log.notice(.sync, "Health: \(result.imported) importiert, \(result.merged) zusammengeführt, \(result.candidates) offen, \(result.removed) entfernt")
        }
        return result
    }

    /// Einträge, die älter als das Importfenster sind, kommen nie wieder (der Import ignoriert sie ohnehin).
    private static func pruned(_ ledger: [HealthLedgerEntry], now: Date) -> [HealthLedgerEntry] {
        let cutoff = now.addingTimeInterval(-Double(healthImportWindowDays + 60) * 86_400)
        return ledger.filter { $0.end >= cutoff || $0.outcome == .candidate }
    }

    private func refreshHealthWeight(now: Date) async {
        do {
            let mean = try await healthSource.bodyMass7DayMean(asOf: now, source: nil)
            healthWeightKg = mean.flatMap { Self.plausibleWeight.contains($0) ? $0 : nil }
            if let kg = healthWeightKg { defaults.set(kg, forKey: HealthKeys.weight) } else { defaults.removeObject(forKey: HealthKeys.weight) }
        } catch {
            Log.error(.sync, "Health-Gewicht nicht lesbar: \(type(of: error))")   // der letzte Wert bleibt
        }
    }

    // MARK: Überlappung

    private static func occupied(for workout: HealthWorkout) -> HealthImport.Occupied {
        HealthImport.Occupied(kind: .ride(importedRideID("health:\(workout.uuid.uuidString)")), start: workout.start,
                              end: workout.end, heartRate: workout.avgHR == nil ? nil : .health)
    }

    /// Fahrten und Krafteinheiten im Zeitfenster der neuen Workouts (± 1 Tag), mit dem Rang ihres Pulses.
    private func healthOccupied(around workouts: [HealthWorkout]) -> [HealthImport.Occupied] {
        guard let first = workouts.map(\.start).min(), let last = workouts.map(\.end).max() else { return [] }
        let low = first.addingTimeInterval(-86_400), high = last.addingTimeInterval(86_400)
        let descriptor = FetchDescriptor<StoredRide>(predicate: #Predicate { $0.startDate >= low && $0.startDate <= high })
        var result: [HealthImport.Occupied] = ((try? context.fetch(descriptor)) ?? []).filter { !$0.isDeleted }.map { row in
            let rank: HealthImport.HeartRateRank?
            if row.healthUUID != nil {
                rank = row.averageHeartrate == nil ? nil : .health
            } else {
                let secondsHR = row.powerCurveData == nil && RideSeconds.decode(row.secondsData)?.heartRate != nil
                rank = HealthImport.rank(hasCurve: row.powerCurveData != nil, hasSecondsHeartRate: secondsHR,
                                         isStrava: row.stravaID > 0, hasHeartRate: row.averageHeartrate != nil)
            }
            return HealthImport.Occupied(kind: .ride(row.stravaID), start: row.startDate,
                                         end: row.startDate.addingTimeInterval(TimeInterval(row.movingTime)), heartRate: rank)
        }
        for row in storedStrengthRows() where row.start >= low && row.start <= high {
            result.append(HealthImport.Occupied(kind: .strength(row.id), start: row.start,
                                                end: row.start.addingTimeInterval(TimeInterval(row.durationSeconds)),
                                                heartRate: row.heartRateSeconds == nil ? nil : .strap))
        }
        return result
    }

    // MARK: Importieren

    /// Speichert das Workout als Fahrt (aerob mit geschätzter TSS, Rad ohne). Nur über `mergeImportedRides`, damit Demo-Daten,
    /// Auswertungen und Caches wie bei jedem Import behandelt werden.
    private func importHealthRide(_ workout: HealthWorkout, estimate: HealthImport.Estimate?, ledger: inout [HealthLedgerEntry]) -> Bool {
        let id = Self.importedRideID("health:\(workout.uuid.uuidString)")
        let name = "\(HealthImport.germanName(for: workout.activityTypeName)) (\(workout.sourceName))"
        var ride = RideSummary(id: id, name: name, sportType: HealthImport.sportType(for: workout.activityTypeName),
                               startDate: workout.start, movingTime: Int(workout.end.timeIntervalSince(workout.start).rounded()),
                               distance: 0, averageHeartrate: workout.avgHR, maxHeartrate: workout.maxHR,
                               trainer: workout.isIndoorCycling)   // Rolle: zählt als Indoor und kann den iPhone-Puls bekommen
        ride.healthUUID = workout.uuid.uuidString
        if let estimate {
            ride.foreignSport = workout.activityTypeName
            ride.estimatedTSS = estimate.tss
        }
        let inserted = mergeImportedRides([ride]).inserted > 0
        ledger.removeAll { $0.uuid == workout.uuid }
        ledger.append(HealthLedgerEntry(workout, outcome: .imported, targetRideID: id))
        return inserted
    }

    /// Führt das Workout in die Fahrt/Einheit zusammen. `false`, wenn das Ziel fehlt (nichts geändert, kein Protokolleintrag).
    func mergeHealthWorkout(_ workout: HealthWorkout, into kind: HealthImport.Occupied.Kind, supplyHeartRate: Bool,
                            ledger: inout [HealthLedgerEntry]) async -> Bool {
        let minutes = Int((workout.end.timeIntervalSince(workout.start) / 60).rounded())
        let note = "Mit Apple-Health-Workout „\(HealthImport.germanName(for: workout.activityTypeName))“ von \(workout.sourceName) "
            + "(\(minutes) min) zusammengeführt\(supplyHeartRate ? " · Puls aus Health ergänzt" : "")."
        switch kind {
        case .ride(let id):
            var descriptor = FetchDescriptor<StoredRide>(predicate: #Predicate { $0.stravaID == id })
            descriptor.fetchLimit = 1
            guard let row = try? context.fetch(descriptor).first else { return false }
            if supplyHeartRate {
                row.averageHeartrate = workout.avgHR
                row.maxHeartrate = workout.maxHR ?? row.maxHeartrate
            }
            if row.mergedHealthUUID == nil {
                row.mergedHealthUUID = workout.uuid.uuidString
                row.healthNote = note
            }
            ledger.append(HealthLedgerEntry(workout, outcome: .merged, targetRideID: id))
        case .strength(let id):
            guard let row = storedStrengthRows().first(where: { $0.id == id }) else { return false }
            if supplyHeartRate, row.heartRateSeconds == nil,
               let hr = (try? await healthSource.heartRateSeconds(for: workout))?.heartRate, hr.contains(where: { $0 > 0 }) {
                row.heartRateSeconds = Data(hr)
            }
            if row.healthNote == nil { row.healthNote = note }
            ledger.append(HealthLedgerEntry(workout, outcome: .merged, targetStrengthID: id))
        }
        invalidateSecondsDigests()
        return true
    }

    /// Das Workout als eigene Einheit (Rad: Fahrt, aerob: Fahrt mit geschätzter TSS, Kraft: offener Kandidat).
    private func importAsOwn(_ workout: HealthWorkout, ledger: inout [HealthLedgerEntry]) -> (imported: Int, candidates: Int) {
        switch workout.category {
        case .cycling:
            return (importHealthRide(workout, estimate: nil, ledger: &ledger) ? 1 : 0, 0)
        case .aerobic:
            let estimate = HealthImport.estimate(for: workout, thresholdHeartRate: profile.thresholdHeartRate, heartRate: profile.heartRateProfile)
            return (importHealthRide(workout, estimate: estimate, ledger: &ledger) ? 1 : 0, 0)
        case .muscular, .mixed:
            ledger.append(HealthLedgerEntry(workout, outcome: .candidate))
            return (0, 1)
        case .ignore:
            return (0, 0)
        }
    }

    /// Hook aus `mergeImportedRides`: eine echte Fahrt ersetzt ein schon importiertes Health-Workout (siehe `RideMerge`).
    /// Die Zeile verliert ihre Health-Herkunft (Löschen in Health darf sie nicht mehr entfernen) und trägt den Hinweis.
    func absorbHealthRide(_ row: StoredRide?, by incoming: RideSummary) {
        guard let row, let uuid = row.healthUUID, incoming.healthUUID == nil else { return }
        row.healthUUID = nil
        row.sourceRaw = nil
        row.foreignSport = nil
        row.estimatedTSS = nil
        row.mergedHealthUUID = uuid
        row.healthNote = "Mit Apple-Health-Workout zusammengeführt (Puls aus Health, wo die Fahrt keinen hat)."
        var ledger = loadHealthLedger()
        if let i = ledger.firstIndex(where: { $0.uuid.uuidString == uuid }) {
            ledger[i].outcome = .merged
            ledger[i].targetRideID = row.stravaID
            saveHealthLedger(ledger)
        }
    }

    /// „Als eigene Einheit behalten“: macht die Zusammenführung an dieser Fahrt rückgängig. Das Health-Workout wird eine
    /// eigene Einheit (Rad: Fahrt, aerob: Fahrt mit geschätzter TSS, Kraft: offener Kandidat) und bleibt es auch beim
    /// nächsten Abgleich. Ein aus Health ergänzter Puls bleibt an der Fahrt.
    public func keepHealthWorkoutSeparate(rideID: Int) {
        var ledger = loadHealthLedger()
        let entries = ledger.filter { $0.outcome == .merged && $0.targetRideID == rideID }
        var descriptor = FetchDescriptor<StoredRide>(predicate: #Predicate { $0.stravaID == rideID })
        descriptor.fetchLimit = 1
        if let row = try? context.fetch(descriptor).first {
            row.mergedHealthUUID = nil
            row.healthNote = nil
        }
        for entry in entries {
            ledger.removeAll { $0.uuid == entry.uuid }
            let workout = entry.workout
            switch workout.category {
            case .cycling:
                _ = importHealthRide(workout, estimate: nil, ledger: &ledger)
            case .aerobic:
                _ = importHealthRide(workout, estimate: HealthImport.estimate(for: workout, thresholdHeartRate: profile.thresholdHeartRate,
                                                                              heartRate: profile.heartRateProfile), ledger: &ledger)
            case .muscular, .mixed, .ignore:
                ledger.append(HealthLedgerEntry(workout, outcome: .candidate))
            }
        }
        try? context.save()
        saveHealthLedger(ledger)
    }

    // MARK: Kandidaten (Kraft, Klettern, Gemischtes)

    /// „Wie hart? Beine?“ beantwortet: speichert das Workout als Krafteinheit bzw. „Andere Einheit“ und schließt die Karte.
    @discardableResult
    public func annotateHealthCandidate(_ uuid: UUID, hardness: Int?, legs: LegInvolvement?) -> StoredStrengthSession? {
        var ledger = loadHealthLedger()
        guard let i = ledger.firstIndex(where: { $0.uuid == uuid && $0.outcome == .candidate }) else { return nil }
        let entry = ledger[i]
        guard let row = annotate(healthWorkout: uuid.uuidString, start: entry.start, duration: entry.end.timeIntervalSince(entry.start),
                                 sport: entry.activityTypeName, hardness: hardness, legs: legs) else { return nil }
        ledger[i].outcome = .annotated
        saveHealthLedger(ledger)
        return row
    }

    /// „Ignorieren“: die Karte verschwindet und kommt für dieses Workout nicht wieder.
    public func dismissHealthCandidate(_ uuid: UUID) {
        var ledger = loadHealthLedger()
        guard let i = ledger.firstIndex(where: { $0.uuid == uuid && $0.outcome == .candidate }) else { return }
        ledger[i].outcome = .dismissed
        saveHealthLedger(ledger)
    }

    // MARK: Löschen in Health

    /// Entfernt, was aus dem gelöschten Workout geworden ist. `true`, wenn es bekannt war.
    private func removeHealthWorkout(_ uuid: UUID, from ledger: inout [HealthLedgerEntry]) -> Bool {
        let text = uuid.uuidString
        let entry = ledger.first { $0.uuid == uuid }
        ledger.removeAll { $0.uuid == uuid }
        var known = entry != nil
        if let rows = try? context.fetch(FetchDescriptor<StoredRide>(predicate: #Predicate { $0.healthUUID == text || $0.mergedHealthUUID == text })) {
            for row in rows {
                known = true
                if row.healthUUID == text { context.delete(row) } else { row.mergedHealthUUID = nil; row.healthNote = nil }
            }
        }
        if entry?.outcome == .merged, let id = entry?.targetStrengthID, let row = storedStrengthRows().first(where: { $0.id == id }) {
            row.healthNote = nil
        }
        if entry?.outcome == .annotated, let row = storedStrengthRows().first(where: { $0.healthUUID == text }) {
            context.delete(row)
        }
        return known
    }
}
