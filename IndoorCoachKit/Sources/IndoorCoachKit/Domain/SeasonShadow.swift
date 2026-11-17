import Foundation

/// Vorjahres-Schatten (G6): the fitness curve of the same window one year earlier, shifted by +1 year so it can be
/// drawn over the current curve. Pure; nil when the previous year has no data.
public enum SeasonShadow {
    public struct Point: Hashable, Sendable, Identifiable {
        /// Plot position: the original day plus one year.
        public var date: Date
        public var fitness: Double
        public var id: Date { date }
    }

    /// Fitness at or below this counts as "no data" (the series is 0 before the first ride).
    static let noDataThreshold = 0.5

    /// - Parameters:
    ///   - points: the full daily fitness series.
    ///   - window: the shown window (current year); the shadow covers the same days one year earlier.
    public static func points(from points: [FitnessFreshness.Point], window: ClosedRange<Date>,
                              calendar: Calendar = .current) -> [Point]? {
        guard let from = calendar.date(byAdding: .year, value: -1, to: window.lowerBound),
              let to = calendar.date(byAdding: .year, value: -1, to: window.upperBound) else { return nil }
        var result: [Point] = []
        for p in points where p.date >= from && p.date <= to {
            guard let shifted = calendar.date(byAdding: .year, value: 1, to: p.date) else { continue }
            // 29 Feb + 1 year lands on 28 Feb: keep one point per plotted day (the later one).
            if let last = result.last, last.date == shifted { result.removeLast() }
            result.append(Point(date: shifted, fitness: p.fitness))
        }
        guard result.contains(where: { $0.fitness > noDataThreshold }) else { return nil }
        return result
    }

    /// Fitness of the shadow on `day` (the last point on or before it), only when the shadow reaches that day.
    public static func fitness(on day: Date, in shadow: [Point], calendar: Calendar = .current) -> Double? {
        guard let last = shadow.last(where: { $0.date <= day }),
              let gap = calendar.dateComponents([.day], from: last.date, to: day).day, gap <= 1 else { return nil }
        return last.fitness
    }

    /// "Heute 34, Vorjahr 29" – the one wording for legend and VoiceOver.
    public static func comparisonText(today: Double, previous: Double?) -> String {
        guard let previous else { return "Heute \(Formatters.decimal(today))" }
        return "Heute \(Formatters.decimal(today)), Vorjahr \(Formatters.decimal(previous))"
    }
}
