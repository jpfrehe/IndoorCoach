import Foundation

/// Data preparation behind the P1 analysis charts (concept 21 §5, AP5). Pure, Foundation only.
public enum ChartSeries {
    // MARK: Form (D6)

    /// Which pole a form value belongs to: > 0 fresher than loaded (fitness blue), ≤ 0 loaded (fatigue pink).
    public enum FormSide: Equatable, Sendable { case recovered, loaded }

    public static func formSide(_ form: Double) -> FormSide { form > 0 ? .recovered : .loaded }

    /// Band "ausgewogen" drawn behind the form bars (concept §5, D6).
    public static let balancedFormBand: ClosedRange<Double> = -10...5

    // MARK: Week bars (D9, D10)

    /// One flag per week: true only for the week that contains `now`. Earlier weeks are muted.
    public static func currentWeekFlags(weekStarts: [Date], now: Date, calendar: Calendar = .current) -> [Bool] {
        weekStarts.map { start in
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: start) else { return false }
            return interval.contains(now)
        }
    }

    // MARK: Soll/Ist (D8)

    public struct TimedValue: Equatable, Sendable {
        public var minute: Double
        public var watts: Double
    }

    /// Maximum number of points a Soll/Ist line carries.
    public static let maxActualPoints = 400

    /// "Ist": 30-s trailing mean over the per-second watts, thinned to ≤ `maxPoints` keeping the extremes.
    public static func smoothedActual(_ actual: [Double], maxPoints: Int = maxActualPoints) -> [TimedValue] {
        let smooth = ChartMath.rollingMean(actual, window: 30)
        return ChartMath.downsampleMinMax(smooth, maxPoints: maxPoints).map { TimedValue(minute: Double($0) / 60, watts: smooth[$0]) }
    }

    /// "Ist" from a series that is already 30-s smoothed (`IntervalCompliance.Result.actualSeries`): thinning only,
    /// so the mean is not applied twice.
    public static func thinnedActual(_ smoothed: [Double], maxPoints: Int = maxActualPoints) -> [TimedValue] {
        ChartMath.downsampleMinMax(smoothed, maxPoints: maxPoints).map { TimedValue(minute: Double($0) / 60, watts: smoothed[$0]) }
    }

    /// "Soll": only the samples around a change (for `.stepEnd`), so edges stay exact; falls back to min/max thinning
    /// when the plan is a long ramp with a change every second.
    public static func targetSteps(_ target: [Double], maxPoints: Int = maxActualPoints) -> [TimedValue] {
        guard !target.isEmpty else { return [] }
        var keep: [Int] = [0]
        for i in 1..<max(target.count, 1) where abs(target[i] - target[i - 1]) > 0.5 {
            if keep.last != i - 1 { keep.append(i - 1) }
            keep.append(i)
        }
        if keep.last != target.count - 1 { keep.append(target.count - 1) }
        if keep.count > maxPoints {
            keep = ChartMath.downsampleMinMax(target, maxPoints: maxPoints)
        }
        return keep.map { TimedValue(minute: Double($0) / 60, watts: target[$0]) }
    }

    /// Value of a series at `minute` (last sample at or before it).
    public static func value(_ series: [TimedValue], atMinute minute: Double) -> Double? {
        series.last { $0.minute <= minute }?.watts ?? series.first?.watts
    }
}
