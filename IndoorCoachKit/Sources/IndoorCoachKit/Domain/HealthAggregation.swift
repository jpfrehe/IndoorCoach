import Foundation

/// Einzelner Messwert mit Quelle (Rohdaten aus Health, vor der Tagesbildung).
public struct HealthSample: Equatable, Sendable {
    public var date: Date
    public var value: Double
    public var source: HealthSourceRef

    public init(date: Date, value: Double, source: HealthSourceRef) {
        self.date = date
        self.value = value
        self.source = source
    }
}

/// Schlafabschnitt; `isAsleep` = eine der „asleep“-Kategorien (nicht inBed/awake).
public struct HealthSleepSegment: Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var isAsleep: Bool
    public var source: HealthSourceRef

    public init(start: Date, end: Date, isAsleep: Bool, source: HealthSourceRef) {
        self.start = start
        self.end = end
        self.isAsleep = isAsleep
        self.source = source
    }
}

/// Reine Aggregationen: Tageswerte je Quelle, Schlaf je Nacht, Puls-Sekunden, Gewichtsmittel.
public enum HealthAggregation {
    /// Mittel je (Tag, Quelle); Körpergewicht: letzter Wert des Tages.
    public static func daily(_ samples: [HealthSample], metric: HealthMetric, calendar: Calendar = .current) -> [HealthDaily] {
        struct Key: Hashable { var day: Date; var source: HealthSourceRef }
        var groups: [Key: [HealthSample]] = [:]
        for s in samples { groups[Key(day: calendar.startOfDay(for: s.date), source: s.source), default: []].append(s) }
        let out = groups.map { key, list -> HealthDaily in
            let value: Double
            if metric == .bodyMass {
                value = list.max { $0.date < $1.date }?.value ?? 0
            } else {
                value = list.reduce(0) { $0 + $1.value } / Double(list.count)
            }
            return HealthDaily(date: key.day, metric: metric, value: value, source: key.source)
        }
        return sorted(out)
    }

    /// `HKCategoryValueSleepAnalysis`: 1 unspecified, 3 core, 4 deep, 5 REM zählen als Schlaf (0 inBed, 2 awake nicht).
    public static func isAsleep(rawValue: Int) -> Bool { [1, 3, 4, 5].contains(rawValue) }

    /// Schlafstunden je Nacht und Quelle: Vereinigung der Schlafabschnitte (Überlappungen zählen einmal). Die Nacht
    /// gehört zum Aufwachtag (Grenze 12 Uhr), nicht zu den Phasen.
    public static func sleepNights(_ segments: [HealthSleepSegment], calendar: Calendar = .current) -> [HealthDaily] {
        struct Key: Hashable { var day: Date; var source: HealthSourceRef }
        var groups: [Key: [(Date, Date)]] = [:]
        for s in segments where s.isAsleep && s.end > s.start {
            let day = calendar.startOfDay(for: s.end.addingTimeInterval(12 * 3600))
            groups[Key(day: day, source: s.source), default: []].append((s.start, s.end))
        }
        let out = groups.map { key, spans -> HealthDaily in
            var total: TimeInterval = 0
            var current: (Date, Date)?
            for span in spans.sorted(by: { $0.0 < $1.0 }) {
                if let c = current, span.0 <= c.1 {
                    current = (c.0, max(c.1, span.1))
                } else {
                    if let c = current { total += c.1.timeIntervalSince(c.0) }
                    current = span
                }
            }
            if let c = current { total += c.1.timeIntervalSince(c.0) }
            return HealthDaily(date: key.day, metric: .sleepHours, value: total / 3600, source: key.source)
        }
        return sorted(out)
    }

    /// Puls als 1-Hz-Reihe über `start..<end` (Leistung 0). Zwischen Messwerten ≤ `interpolationGap` linear
    /// interpoliert, sonst letzter Wert für höchstens `holdLimit`; danach 0 (keine Messung). `nil` ohne Puls.
    public static func heartRateSeconds(_ samples: [HealthSample], start: Date, end: Date,
                                        interpolationGap: TimeInterval = 15, holdLimit: TimeInterval = 60) -> RideSeconds? {
        let seconds = Int(end.timeIntervalSince(start).rounded(.up))
        guard seconds > 0, seconds <= FITParser.maxSeriesSeconds else { return nil }
        let pts = samples.filter { $0.value > 0 && $0.date <= end }.sorted { $0.date < $1.date }
        guard !pts.isEmpty else { return nil }
        var bpm = [Double](repeating: 0, count: seconds)
        var i = 0   // Index des letzten Messwerts mit date <= t (oder 0 davor)
        for s in 0..<seconds {
            let t = start.addingTimeInterval(TimeInterval(s))
            while i + 1 < pts.count, pts[i + 1].date <= t { i += 1 }
            let prev = pts[i]
            if prev.date > t {
                if prev.date.timeIntervalSince(t) <= holdLimit { bpm[s] = prev.value }
                continue
            }
            if i + 1 < pts.count {
                let next = pts[i + 1]
                let gap = next.date.timeIntervalSince(prev.date)
                if gap <= interpolationGap {
                    let f = t.timeIntervalSince(prev.date) / gap
                    bpm[s] = prev.value + (next.value - prev.value) * f
                    continue
                }
            }
            if t.timeIntervalSince(prev.date) <= holdLimit { bpm[s] = prev.value }
        }
        return RideSeconds(watts: [Double](repeating: 0, count: seconds), beatsPerMinute: bpm)
    }

    /// Mittel der Körpergewicht-Tageswerte der letzten 7 Tage (inkl. Tag von `asOf`), `nil` ohne Werte.
    public static func mean7Day(_ dailies: [HealthDaily], asOf: Date, calendar: Calendar = .current) -> Double? {
        let end = calendar.startOfDay(for: asOf)
        guard let from = calendar.date(byAdding: .day, value: -6, to: end) else { return nil }
        let v = dailies.filter { $0.metric == .bodyMass && $0.date >= from && $0.date <= end }.map(\.value)
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }

    private static func sorted(_ list: [HealthDaily]) -> [HealthDaily] {
        list.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return ($0.source.name, $0.source.bundleID) < ($1.source.name, $1.source.bundleID)
        }
    }
}
