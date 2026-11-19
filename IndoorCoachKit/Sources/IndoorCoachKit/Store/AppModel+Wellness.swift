import Foundation
import SwiftData

/// Erholungswerte (Ruhepuls, HRV, Schlaf, Atemfrequenz, Handgelenktemperatur) als Trend und der Trend-Wächter
/// (docs/17 §2.1, §2.2, §9.7; B52, B53, B55). Tageswerte kommen nur mit aktiviertem Health, nur aus der gepinnten
/// Quelle und liegen als JSON im lokalen Application Support (kein iCloud, nie im Protokoll: nur Zähler).
@MainActor
private enum WellnessStore {
    struct State {
        var dailies: [HealthDaily] = []
        var loaded = false
        /// Verzeichnis des Caches (Tests setzen ein eigenes).
        var directory: URL?
    }
    static var states: [ObjectIdentifier: State] = [:]
}

/// Was die Karte „Heute“ braucht: die nächste harte Einheit, warum der Wächter anschlägt und die Angebote.
public struct TrendHint {
    public var workout: StoredWorkout
    public var result: TrendGuard.Result
    public var offers: [CheckIn.Action]
}

extension AppModel {
    // MARK: Schlüssel und Orte

    /// Pins je Kennzahl, geschrieben von `DefaultHealthSettings` (Datenquellen-Ansicht).
    static let wellnessPinsKey = "dataSources.pins.v1"
    static let wellnessShadowKey = "wellness.shadow.enabled.v1"
    static let wellnessShadowHitsKey = "wellness.shadow.hits.v1"
    static let wellnessShadowDaysKey = "wellness.shadow.days.v1"
    static let wellnessShadowLastHitKey = "wellness.shadow.lastHit.v1"
    static let wellnessShadowLastEvalKey = "wellness.shadow.lastEval.v1"
    static let wellnessDismissedKey = "wellness.hint.dismissedDay.v1"
    static let wellnessStateKeys = [wellnessShadowKey, wellnessShadowHitsKey, wellnessShadowDaysKey, wellnessShadowLastHitKey,
                                    wellnessShadowLastEvalKey, wellnessDismissedKey]
    static let wellnessCacheFile = "wellness-cache.v1.json"

    /// Kennzahlen, die der Cache hält.
    static let wellnessMetrics: [HealthMetric] = [.restingHR, .hrvSDNN, .sleepHours, .respiratoryRate, .wristTempDelta]
    /// Fenster, das beim Abgleich geholt wird (28 Tage Basis plus Puffer).
    static let wellnessFetchDays = 35
    /// Der Wächter meldet sich nur, wenn die nächste Einheit höchstens so viele Tage entfernt ist (heute eingeschlossen).
    static let wellnessHintHorizonDays = 3

    /// Später liefert ein anderes Paket das Morgen-HRV-Signal (`nil` = unbekannt).
    public static var morningHRVSignalProvider: (() -> Bool?)?

    private static var defaultWellnessDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Wellness", directoryHint: .isDirectory)
    }

    private var wellnessKey: ObjectIdentifier { ObjectIdentifier(self) }

    // MARK: Cache

    private struct CachedDaily: Codable {
        var date: Date
        var metric: String
        var value: Double
        var source: String
        var bundleID: String
    }

    private func wellnessDirectory() -> URL { WellnessStore.states[wellnessKey]?.directory ?? Self.defaultWellnessDirectory }

    private func loadWellnessIfNeeded() {
        var state = WellnessStore.states[wellnessKey] ?? .init()
        guard !state.loaded else { return }
        state.loaded = true
        let url = (state.directory ?? Self.defaultWellnessDirectory).appendingPathComponent(Self.wellnessCacheFile)
        if let data = try? Data(contentsOf: url), let rows = try? JSONDecoder().decode([CachedDaily].self, from: data) {
            state.dailies = rows.compactMap { row in
                HealthMetric(rawValue: row.metric).map {
                    HealthDaily(date: row.date, metric: $0, value: row.value, source: HealthSourceRef(name: row.source, bundleID: row.bundleID))
                }
            }
        }
        WellnessStore.states[wellnessKey] = state
    }

    private func saveWellnessCache() {
        guard let state = WellnessStore.states[wellnessKey] else { return }
        let dir = state.directory ?? Self.defaultWellnessDirectory
        let rows = state.dailies.map { CachedDaily(date: $0.date, metric: $0.metric.rawValue, value: $0.value, source: $0.source.name, bundleID: $0.source.bundleID) }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var options: Data.WritingOptions = [.atomic]
            #if os(iOS)
            options.insert(.completeFileProtection)
            #endif
            try JSONEncoder().encode(rows).write(to: dir.appendingPathComponent(Self.wellnessCacheFile), options: options)
        } catch {
            Log.error(.sync, "Erholungswerte nicht gespeichert: \(type(of: error))")
        }
    }

    // MARK: Laden

    /// Holt die Tageswerte der letzten 35 Tage aus Health und legt sie im lokalen Cache ab. Nur mit aktiviertem Health;
    /// ohne verfügbare Quelle bleibt der Cache. Danach wertet der Schattenmodus aus (falls an).
    public func refreshWellness(now: Date = .now) async { await refreshWellness(now: now, directory: nil) }

    func refreshWellness(now: Date, directory: URL?) async {
        guard healthEnabled else { return }
        var state = WellnessStore.states[wellnessKey] ?? .init()
        if let directory { state.directory = directory }
        WellnessStore.states[wellnessKey] = state
        loadWellnessIfNeeded()
        guard healthSource.isAvailable else { return }
        let calendar = Calendar.current
        guard let from = calendar.date(byAdding: .day, value: -Self.wellnessFetchDays, to: calendar.startOfDay(for: now)) else { return }
        var fetchedAny = false
        for metric in Self.wellnessMetrics {
            do {
                let rows = try await healthSource.dailyValues(metric, in: from...now)
                var current = WellnessStore.states[wellnessKey] ?? .init()
                current.dailies.removeAll { $0.metric == metric }
                current.dailies += rows
                WellnessStore.states[wellnessKey] = current
                fetchedAny = true
            } catch {
                Log.error(.sync, "Health-Erholungswerte nicht lesbar: \(type(of: error))")   // der Cache dieser Kennzahl bleibt
            }
        }
        if fetchedAny { saveWellnessCache() }
        recordShadowEvaluation(now: now)
    }

    // MARK: Trend

    /// Gepinnte Quelle je Kennzahl (Datenquellen-Ansicht); ohne Pin zählt die Quelle des neuesten Werts.
    private func wellnessPins() -> HealthSourcePins {
        defaults.data(forKey: Self.wellnessPinsKey).flatMap { try? JSONDecoder().decode(HealthSourcePins.self, from: $0) } ?? HealthSourcePins()
    }

    /// Trend einer Kennzahl; leer (nie „fertig“), solange Health aus ist oder zu wenige Tage vorliegen.
    public func wellnessTrend(_ kind: HealthMetric, now: Date = .now) -> WellnessTrend {
        guard healthEnabled else { return .empty(kind) }
        loadWellnessIfNeeded()
        let dailies = HealthSourcePinning.filter(WellnessStore.states[wellnessKey]?.dailies ?? [], pins: wellnessPins())
        return WellnessTrend.make(metric: kind, dailies: dailies, asOf: now)
    }

    // MARK: Wächter

    private struct CheckInSignals {
        var lastNegative = false
        var lastInfection = false
        var negativeCount = 0
    }

    /// Check-ins der letzten 3 Tage (ohne übersprungene).
    private func recentCheckIns(now: Date) -> [StoredCheckIn] {
        let calendar = Calendar.current
        guard let from = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: now)) else { return [] }
        let rows = (try? context.fetch(FetchDescriptor<StoredCheckIn>(predicate: #Predicate { $0.day >= from }, sortBy: [SortDescriptor(\.day)]))) ?? []
        return rows.filter { !$0.skipped && !$0.isDeleted }
    }

    private func checkInSignals(now: Date) -> CheckInSignals {
        let rows = recentCheckIns(now: now)
        var signals = CheckInSignals()
        // Negativ: mindestens zwei schlechte Antworten (Infekt zählt als eigenes Signal).
        if let last = rows.last?.answers {
            signals.lastNegative = last.negativeCount >= 2
            signals.lastInfection = last.hasInfection
        }
        signals.negativeCount = rows.filter { $0.answers.offerNeeded }.count
        return signals
    }

    /// Aufwärm-Puls des letzten Checks gegen den Median der früheren; nil, wenn der letzte Check älter als 3 Tage ist.
    private func warmupDeltaBpm(now: Date) -> Double? {
        let calendar = Calendar.current
        guard let from = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: now)) else { return nil }
        let since = profile.warmupCheckBaseSince
        let rides = allRides().filter { $0.trainer && $0.startDate >= (since ?? .distantPast) && $0.startDate <= now }
            .sorted { $0.startDate > $1.startDate }.prefix(60)
        let checks = rides.compactMap { warmupCheck(for: $0) }.filter(\.valid)
        guard let newest = checks.map(\.date).max(), newest >= from else { return nil }
        return TrendGuard.warmupDelta(checks: checks, refWatts: profile.effectiveWarmupCheckWatts)
    }

    /// Wertet den Wächter aus den Trends, dem letzten Check-in und (für S0) dem Aufwärm-Check aus. Ohne Health: ruhig.
    /// `morningHRVSignal` überschreibt `AppModel.morningHRVSignalProvider` (Einhängepunkt für das Morgen-HRV-Paket).
    public func trendGuardResult(now: Date = .now, morningHRVSignal: (() -> Bool?)? = nil) -> TrendGuard.Result {
        guard healthEnabled else { return .quiet }
        let rhr = wellnessTrend(.restingHR, now: now)
        let signals = checkInSignals(now: now)
        let hrvPin = wellnessPins().pins[.hrvSDNN]
        let watchPinned = hrvPin.map { $0.source.name.localizedCaseInsensitiveContains("Watch") || $0.source.bundleID.hasPrefix("com.apple.health") } ?? false
        let input = TrendGuard.Input(restingHR: rhr, respiratoryRate: wellnessTrend(.respiratoryRate, now: now),
                                     wristTemperature: wellnessTrend(.wristTempDelta, now: now),
                                     hrv: wellnessTrend(.hrvSDNN, now: now), hrvWatchPinned: watchPinned,
                                     lastCheckInNegative: signals.lastNegative, lastCheckInInfection: signals.lastInfection,
                                     negativeCheckIns3Days: signals.negativeCount,
                                     warmupDeltaBpm: rhr.isReady ? nil : warmupDeltaBpm(now: now),
                                     morningHRVSignal: (morningHRVSignal ?? Self.morningHRVSignalProvider)?())
        return TrendGuard.evaluate(input)
    }

    // MARK: Karte „Heute“

    /// Der Wächter schlägt an und die nächste geplante Einheit (heute bis in 2 Tagen) ist hart.
    private func trendGuardCandidate(now: Date) -> (workout: StoredWorkout, result: TrendGuard.Result)? {
        let result = trendGuardResult(now: now)
        guard result.isTriggered else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: Self.wellnessHintHorizonDays, to: start) else { return nil }
        let all = (try? context.fetch(FetchDescriptor<StoredWorkout>(sortBy: [SortDescriptor(\.date)]))) ?? []
        guard let next = all.first(where: { !$0.isDeleted && $0.status == .planned && $0.date >= start }),
              next.date < end, TrendGuard.isHard((next.originalDefinition ?? next.definition).type) else { return nil }
        return (next, result)
    }

    /// Die ruhige Karte für „Heute“: nur außerhalb des Schattenmodus, nur einmal pro Tag wegklickbar, nicht für eine
    /// bereits angepasste Einheit.
    public func trendHint(now: Date = .now) -> TrendHint? {
        guard !trendGuardShadowMode, let (workout, result) = trendGuardCandidate(now: now), workout.originalSegmentsData == nil else { return nil }
        let day = Calendar.current.startOfDay(for: now).timeIntervalSince1970
        if defaults.object(forKey: Self.wellnessDismissedKey) as? Double == day { return nil }
        let definition = workout.originalDefinition ?? workout.definition
        let canSwap = ![WorkoutType.endurance, .recovery].contains(definition.type) && WorkoutSwap.base(for: definition) != nil
        let jokers = consistency(rides: allRides(), now: now).jokers
        let offers = CheckIn.offers(for: CheckIn.Answers(legs: .bad, sleep: .bad), plannedMinutes: WorkoutAdjust.minutes(definition.totalDuration),
                                    jokersAvailable: jokers, canSwap: canSwap)
        return TrendHint(workout: workout, result: result, offers: offers)
    }

    /// „Passt schon“: die Karte bleibt für heute weg.
    public func dismissTrendHint(now: Date = .now) {
        defaults.set(Calendar.current.startOfDay(for: now).timeIntervalSince1970, forKey: Self.wellnessDismissedKey)
    }

    // MARK: Schattenmodus

    /// Schalter im Diagnosebereich (Standard aus). An: Treffer werden nur gezählt, es erscheint keine Karte.
    public var trendGuardShadowMode: Bool {
        get { defaults.bool(forKey: Self.wellnessShadowKey) }
        set { defaults.set(newValue, forKey: Self.wellnessShadowKey) }
    }

    /// Treffer (Karte wäre erschienen) und ausgewertete Tage seit dem Einschalten; nie Werte.
    public var trendGuardShadowStats: (hits: Int, days: Int) {
        (defaults.integer(forKey: Self.wellnessShadowHitsKey), defaults.integer(forKey: Self.wellnessShadowDaysKey))
    }

    /// Eine Zeile für den Diagnose-Export.
    var trendGuardShadowSummary: String {
        let stats = trendGuardShadowStats
        return "\(trendGuardShadowMode ? "an" : "aus"), Treffer: \(stats.hits) an \(stats.days) ausgewerteten Tagen"
    }

    /// Höchstens eine Auswertung und ein Treffer pro Tag.
    private func recordShadowEvaluation(now: Date) {
        guard trendGuardShadowMode else { return }
        let day = Calendar.current.startOfDay(for: now).timeIntervalSince1970
        if defaults.object(forKey: Self.wellnessShadowLastEvalKey) as? Double != day {
            defaults.set(day, forKey: Self.wellnessShadowLastEvalKey)
            defaults.set(defaults.integer(forKey: Self.wellnessShadowDaysKey) + 1, forKey: Self.wellnessShadowDaysKey)
        }
        guard trendGuardCandidate(now: now) != nil, defaults.object(forKey: Self.wellnessShadowLastHitKey) as? Double != day else { return }
        defaults.set(day, forKey: Self.wellnessShadowLastHitKey)
        defaults.set(defaults.integer(forKey: Self.wellnessShadowHitsKey) + 1, forKey: Self.wellnessShadowHitsKey)
        Log.notice(.app, "Trend-Wächter (Schattenmodus): Treffer")
    }

    // MARK: Löschen

    /// „Alle Daten löschen“: Cache im Speicher und auf der Platte, Schattenzähler, Schalter und Wegklick-Merker.
    public func resetWellnessState() {
        let directories = [WellnessStore.states[wellnessKey]?.directory, Self.defaultWellnessDirectory].compactMap { $0 }
        for dir in directories { try? FileManager.default.removeItem(at: dir.appendingPathComponent(Self.wellnessCacheFile)) }
        WellnessStore.states[wellnessKey] = nil
        for key in Self.wellnessStateKeys { defaults.removeObject(forKey: key) }
    }
}
