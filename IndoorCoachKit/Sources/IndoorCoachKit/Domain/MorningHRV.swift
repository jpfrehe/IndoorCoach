import Foundation

/// Morgenmessung HRV mit Brustgurt (B54, J-D): 60 s liegend, Auswertung, Qualitätsregel und Trend.
/// Nur Trend, nie ein Tageswert: 7-Tage-Mittel lnRMSSD gegen die 28-Tage-Basis. Keine Ampel, kein Push.
public enum MorningHRV {
    public static let duration: TimeInterval = 60
    public static let minQuality = 0.8
    public static let minBeats = 40
    public static let minMeasurementsForTrend = 3
    public static let trendDays = 7
    public static let baselineDays = 28
    /// Die Messung wird nur am Vormittag angeboten.
    public static let latestStartHour = 11

    public struct Measurement: Codable, Equatable, Sendable {
        /// Beginn des Tages (lokal), pro Tag zählt eine Messung.
        public var day: Date
        public var lnRMSSD: Double
        public var beats: Int
        public var quality: Double
        public var measuredAt: Date

        public init(day: Date, lnRMSSD: Double, beats: Int, quality: Double, measuredAt: Date) {
            self.day = day
            self.lnRMSSD = lnRMSSD
            self.beats = beats
            self.quality = quality
            self.measuredAt = measuredAt
        }
    }

    public enum DiscardReason: Equatable, Sendable { case tooFewBeats, lowQuality }

    public enum Outcome: Equatable, Sendable {
        case valid(Measurement)
        case discarded(DiscardReason)
    }

    /// Wertet die RR-Folge einer Messung aus. Verworfen bei weniger als 40 gültigen Schlägen oder unter 80 % gültigen RR.
    public static func evaluate(rr: [Double], now: Date, calendar: Calendar = .current) -> Outcome {
        let result = HRV.analyze(rr)
        guard result.accepted >= minBeats else { return .discarded(.tooFewBeats) }
        guard result.quality >= minQuality else { return .discarded(.lowQuality) }
        guard let ln = result.lnRMSSD else { return .discarded(.tooFewBeats) }
        return .valid(Measurement(day: calendar.startOfDay(for: now), lnRMSSD: ln, beats: result.accepted,
                                  quality: result.quality, measuredAt: now))
    }

    public static func progress(elapsed: TimeInterval) -> Double { min(max(elapsed / duration, 0), 1) }

    /// Fügt eine Messung ein: pro Tag nur eine (die neue ersetzt die alte), alles außerhalb der Basis wird gekappt.
    public static func upserting(_ new: Measurement, into list: [Measurement], now: Date, calendar: Calendar = .current) -> [Measurement] {
        let cutoff = windowStart(days: baselineDays, now: now, calendar: calendar)
        var out = list.filter { $0.day != new.day && $0.day >= cutoff }
        out.append(new)
        return out.sorted { $0.day < $1.day }
    }

    // MARK: Trend

    public enum Status: Equatable, Sendable {
        case below, usual, above

        public var text: String {
            switch self {
            case .below: "Dein 7-Tage-Mittel liegt unter deinem üblichen Bereich."
            case .usual: "Dein 7-Tage-Mittel liegt in deinem üblichen Bereich."
            case .above: "Dein 7-Tage-Mittel liegt über deinem üblichen Bereich."
            }
        }
    }

    public struct Trend: Equatable, Sendable {
        public var weekMean: Double
        public var baselineMean: Double
        public var baselineSD: Double
        public var weekCount: Int
        public var status: Status
    }

    /// Nil, solange weniger als 3 Messungen in den letzten 7 Tagen vorliegen.
    public static func trend(_ list: [Measurement], now: Date, calendar: Calendar = .current) -> Trend? {
        let weekStart = windowStart(days: trendDays, now: now, calendar: calendar)
        let baseStart = windowStart(days: baselineDays, now: now, calendar: calendar)
        let week = list.filter { $0.day >= weekStart }
        let base = list.filter { $0.day >= baseStart }
        guard week.count >= minMeasurementsForTrend else { return nil }
        let weekMean = week.map(\.lnRMSSD).reduce(0, +) / Double(week.count)
        let baseMean = base.map(\.lnRMSSD).reduce(0, +) / Double(base.count)
        let variance = base.count > 1 ? base.map { ($0.lnRMSSD - baseMean) * ($0.lnRMSSD - baseMean) }.reduce(0, +) / Double(base.count - 1) : 0
        let sd = variance.squareRoot()
        let status: Status = weekMean < baseMean - sd ? .below : (weekMean > baseMean + sd ? .above : .usual)
        return Trend(weekMean: weekMean, baselineMean: baseMean, baselineSD: sd, weekCount: week.count, status: status)
    }

    /// Wie viele Messungen in den letzten 7 Tagen bis zum ersten Trend noch fehlen (0 = Trend vorhanden).
    public static func measurementsUntilTrend(_ list: [Measurement], now: Date, calendar: Calendar = .current) -> Int {
        let weekStart = windowStart(days: trendDays, now: now, calendar: calendar)
        return max(0, minMeasurementsForTrend - list.filter { $0.day >= weekStart }.count)
    }

    /// Für den Trend-Wächter: true = 7-Tage-Mittel unter dem üblichen Bereich, false = nicht darunter, nil = kein Trend.
    public static func signalBelowBaseline(_ list: [Measurement], now: Date, calendar: Calendar = .current) -> Bool? {
        trend(list, now: now, calendar: calendar).map { $0.status == .below }
    }

    private static func windowStart(days: Int, now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
    }
}
