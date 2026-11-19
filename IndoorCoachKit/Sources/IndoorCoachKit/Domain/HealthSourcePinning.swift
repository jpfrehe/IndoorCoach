import Foundation

/// Gepinnte Quelle je Kennzahl. Mehrere Quellen für denselben Wert (Watch + Garmin) würden Basislinien mischen.
public struct HealthSourcePin: Equatable, Codable, Sendable {
    public var source: HealthSourceRef
    /// Beginn der Basis dieser Quelle; ältere Werte zählen nicht. `nil` = gesamte Historie.
    public var since: Date?
}

public struct HealthSourcePins: Equatable, Codable, Sendable {
    public private(set) var pins: [HealthMetric: HealthSourcePin] = [:]

    public init() {}

    /// Gleiche Quelle: nichts ändert sich. Quellenwechsel: neue Basis ab `date`.
    public mutating func pin(_ source: HealthSourceRef, for metric: HealthMetric, from date: Date?) {
        if pins[metric]?.source == source { return }
        pins[metric] = HealthSourcePin(source: source, since: date)
    }

    public mutating func unpin(_ metric: HealthMetric) { pins[metric] = nil }
}

public enum HealthSourcePinning {
    /// Vorschlag: Quelle mit den meisten Tageswerten der letzten `windowDays` Tage; bei Gleichstand nach Name.
    public static func suggestion(from dailies: [HealthDaily], metric: HealthMetric, now: Date,
                                  windowDays: Int = 28, calendar: Calendar = .current) -> HealthSourceRef? {
        guard let from = calendar.date(byAdding: .day, value: -windowDays, to: calendar.startOfDay(for: now)) else { return nil }
        var counts: [HealthSourceRef: Int] = [:]
        for d in dailies where d.metric == metric && d.date > from && d.date <= now { counts[d.source, default: 0] += 1 }
        return counts.max { a, b in
            a.value != b.value ? a.value < b.value : (a.key.name, a.key.bundleID) > (b.key.name, b.key.bundleID)
        }?.key
    }

    /// Gepinnte Kennzahlen behalten nur Werte der gepinnten Quelle ab Basisdatum; ungepinnte bleiben unverändert.
    public static func filter(_ dailies: [HealthDaily], pins: HealthSourcePins) -> [HealthDaily] {
        dailies.filter { d in
            guard let pin = pins.pins[d.metric] else { return true }
            return d.source == pin.source && (pin.since.map { d.date >= $0 } ?? true)
        }
    }
}
