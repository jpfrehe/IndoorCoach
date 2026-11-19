import Foundation

// Erholungswerte als Trend statt Tageswert (docs/17 §2.1, §2.2, §9.1; B52). Eigene Basis = Median der letzten 28 Tage,
// Anzeige erst ab 21 Tagen mit Werten, eine Quelle je Kennzahl (bei Quellenwechsel startet die Basis neu). Kein
// Gesundheitswert wird je protokolliert; alles hier ist rein rechnerisch.

/// Kleine Statistik-Helfer.
public enum Wellness {
    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    /// Median der absoluten Abweichungen vom Median (roh, ohne Skalierungsfaktor).
    public static func mad(_ values: [Double]) -> Double? {
        guard let m = median(values) else { return nil }
        return median(values.map { abs($0 - m) })
    }

    /// Stichproben-Standardabweichung (n − 1); 0 bei weniger als zwei Werten.
    static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return (values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)).squareRoot()
    }
}

/// Trend einer Kennzahl aus einer Quelle: Tageswerte der letzten 28 Tage, Basis (Median), Streuung (MAD) und Mittel.
public struct WellnessTrend: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public var date: Date
        public var value: Double
        public init(date: Date, value: Double) { self.date = date; self.value = value }
    }

    public static let baselineDays = 28
    /// Mindestzahl Tage mit Werten, ab der Basis und Anzeige gelten.
    public static let minDays = 21
    /// 3-Tage-Mittel: mindestens so viele Werte im Fenster.
    static let mean3MinCount = 2
    /// 7-Tage-Mittel: mindestens so viele Werte im Fenster.
    static let mean7MinCount = 4

    public var metric: HealthMetric
    /// Quelle der Werte (die des neuesten Werts); nil ohne Werte.
    public var source: HealthSourceRef?
    /// Ein Wert je Tag im 28-Tage-Fenster, aufsteigend.
    public var points: [Point]
    public var baseline: Double?
    public var mad: Double?
    public var mean3: Double?
    public var mean7: Double?
    /// HRV: Basis (Median), Streuung (SD) und 7-Tage-Mittel von ln(SDNN); nur für `.hrvSDNN` belegt.
    public var lnBaseline: Double?
    public var lnSD: Double?
    public var lnMean7: Double?

    public var dayCount: Int { points.count }
    public var isReady: Bool { dayCount >= Self.minDays }

    public static func empty(_ metric: HealthMetric) -> WellnessTrend {
        WellnessTrend(metric: metric, source: nil, points: [], baseline: nil, mad: nil, mean3: nil, mean7: nil,
                      lnBaseline: nil, lnSD: nil, lnMean7: nil)
    }

    /// Baut den Trend. Es zählt nur die Quelle des neuesten Werts (Quellenwechsel = neue Basis). Basis, MAD und
    /// Streuung gibt es erst ab `minDays` Tagen mit Werten; die Mittel brauchen nur ihr Fenster.
    public static func make(metric: HealthMetric, dailies: [HealthDaily], asOf: Date, calendar: Calendar = .current) -> WellnessTrend {
        let today = calendar.startOfDay(for: asOf)
        guard let first = calendar.date(byAdding: .day, value: -(baselineDays - 1), to: today),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return .empty(metric) }
        let mine = dailies.filter { $0.metric == metric && $0.date < tomorrow && $0.value.isFinite }
        guard let latest = mine.max(by: { a, b in
            a.date != b.date ? a.date < b.date : (a.source.name, a.source.bundleID) > (b.source.name, b.source.bundleID)
        }) else { return .empty(metric) }
        var byDay: [Date: Double] = [:]
        for d in mine where d.source == latest.source && d.date >= first {
            byDay[calendar.startOfDay(for: d.date)] = d.value
        }
        let points = byDay.map { Point(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }
        var trend = WellnessTrend.empty(metric)
        trend.source = latest.source
        trend.points = points
        trend.mean3 = mean(points, last: 3, minCount: mean3MinCount, today: today, calendar: calendar)
        trend.mean7 = mean(points, last: 7, minCount: mean7MinCount, today: today, calendar: calendar)
        guard trend.isReady else { return trend }
        let values = points.map(\.value)
        trend.baseline = Wellness.median(values)
        trend.mad = Wellness.mad(values)
        if metric == .hrvSDNN {
            let logs = values.filter { $0 > 0 }.map { log($0) }
            trend.lnBaseline = Wellness.median(logs)
            trend.lnSD = Wellness.standardDeviation(logs)
            let from = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            let recent = points.filter { $0.value > 0 && $0.date >= from }
            trend.lnMean7 = recent.count >= mean7MinCount ? recent.map { log($0.value) }.reduce(0, +) / Double(recent.count) : nil
        }
        return trend
    }

    private static func mean(_ points: [Point], last days: Int, minCount: Int, today: Date, calendar: Calendar) -> Double? {
        guard let from = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return nil }
        let values = points.filter { $0.date >= from }.map(\.value)
        return values.count >= minCount ? values.reduce(0, +) / Double(values.count) : nil
    }
}
