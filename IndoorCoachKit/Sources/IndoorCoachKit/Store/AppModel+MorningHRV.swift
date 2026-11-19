import Foundation

/// Speicher der Morgenmessung: JSON in Application Support, Opt-in in UserDefaults (nie Standard).
public struct MorningHRVStore {
    public static let enabledKey = "morningHRV.enabled.v1"

    public static var defaultURL: URL { URL.applicationSupportDirectory.appendingPathComponent("morning-hrv.json") }

    let url: URL
    let defaults: UserDefaults

    public init(url: URL = Self.defaultURL, defaults: UserDefaults = .standard) {
        self.url = url
        self.defaults = defaults
    }

    public var enabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    public func measurements() -> [MorningHRV.Measurement] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([MorningHRV.Measurement].self, from: data)) ?? []
    }

    /// Eine Messung pro Tag: die neue ersetzt die erste desselben Tages.
    public func save(_ measurement: MorningHRV.Measurement, now: Date = .now, calendar: Calendar = .current) {
        let list = MorningHRV.upserting(measurement, into: measurements(), now: now, calendar: calendar)
        guard let data = try? JSONEncoder().encode(list) else { return }
        do { try ProtectedFile.write(data, to: url) } catch { Log.error(.sync, "Morgenmessung nicht gespeichert: \(type(of: error))") }
    }

    public func hasMeasurement(on date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        return measurements().contains { $0.day == day }
    }

    /// Aktiviert, heute noch nicht gemessen und vor 11 Uhr.
    public func isDue(now: Date = .now, calendar: Calendar = .current) -> Bool {
        enabled && calendar.component(.hour, from: now) < MorningHRV.latestStartHour && !hasMeasurement(on: now, calendar: calendar)
    }

    public func reset() {
        try? FileManager.default.removeItem(at: url)
        defaults.removeObject(forKey: Self.enabledKey)
    }
}

extension AppModel {
    /// Für den Trend-Wächter: true = unter dem üblichen Bereich, false = nicht darunter, nil = aus oder kein Trend.
    public func morningHRVSignal(store: MorningHRVStore? = nil, now: Date = .now) -> Bool? {
        let store = store ?? MorningHRVStore(url: morningHRVStoreURL, defaults: defaults)
        guard store.enabled else { return nil }
        return MorningHRV.signalBelowBaseline(store.measurements(), now: now)
    }

    /// „Alle Daten löschen“: Messungen und Opt-in entfernen.
    public func resetMorningHRVState(store: MorningHRVStore? = nil) {
        (store ?? MorningHRVStore(url: morningHRVStoreURL, defaults: defaults)).reset()
    }
}
