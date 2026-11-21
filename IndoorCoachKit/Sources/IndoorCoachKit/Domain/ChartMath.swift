import Foundation

/// Pure helpers behind the shared chart building blocks (concept 21 §3.3/§3.4/§6). Foundation only.
public enum ChartMath {
    // MARK: Axes

    /// "Nice" axis values (steps of 1, 2, 5 × 10ⁿ) that cover `min…max` with roughly `count` ticks. Never empty.
    public static func niceTicks(min lo: Double, max hi: Double, count: Int) -> [Double] {
        var lo = lo, hi = hi
        if lo > hi { swap(&lo, &hi) }
        if !lo.isFinite || !hi.isFinite { return [0, 1] }
        if hi - lo < 1e-12 {
            let pad = Swift.max(abs(lo) * 0.1, 1)
            lo -= pad; hi += pad
        }
        let raw = (hi - lo) / Double(Swift.max(count - 1, 1))
        let mag = pow(10, floor(log10(raw)))
        let step = [1.0, 2, 5, 10].map { $0 * mag }.first { $0 >= raw * (1 - 1e-9) } ?? 10 * mag
        let first = Int(floor(lo / step + 1e-9)), last = Int(ceil(hi / step - 1e-9))
        let ticks = (first...Swift.max(first, last)).map { round(Double($0) * step * 1e9) / 1e9 }
        return ticks.count >= 2 ? ticks : [ticks[0], ticks[0] + step]
    }

    /// Y domain for `values`. Never collapses: equal values give ±1, no values give 0…1.
    /// Without `includeZero` the span gets 8 % padding so the line does not touch the plot edges.
    public static func domain(values: [Double], includeZero: Bool) -> ClosedRange<Double> {
        let finite = values.filter(\.isFinite)
        guard var lo = finite.min(), var hi = finite.max() else { return 0...1 }
        if includeZero { lo = Swift.min(lo, 0); hi = Swift.max(hi, 0) }
        if hi - lo < 1e-12 { return (lo - 1)...(hi + 1) }
        if !includeZero {
            let pad = (hi - lo) * 0.08
            lo -= pad; hi += pad
        }
        return lo...hi
    }

    /// X ticks in minutes for a session of `total` seconds: at most four steps of 5/10/15/30/60 min, starting at 0.
    public static func minuteTicks(total: TimeInterval) -> [Double] {
        let minutes = Swift.max(total, 0) / 60
        guard minutes > 0 else { return [0] }
        let step = [5.0, 10, 15, 30, 60, 120].first { minutes / $0 <= 4 } ?? 120
        return (0...Int(minutes / step + 1e-9)).map { Double($0) * step }
    }

    /// X ticks in seconds for the log-scaled power curve. 60 min only appears with ≥ 45 min of data (it crowds 20 min).
    public static func powerCurveTicks(maxDuration: TimeInterval) -> [Double] {
        var ticks: [Double] = [5]
        for t in [60.0, 300, 1200] where t <= maxDuration { ticks.append(t) }
        if maxDuration >= 45 * 60 { ticks.append(3600) }
        return ticks
    }

    // MARK: Smoothing and thinning

    /// Trailing mean over `window` samples. Samples ≤ 0 are pauses/dropouts and are left out of the mean;
    /// a window with only pauses yields 0. Output has the same length as the input.
    public static func rollingMean(_ values: [Double], window: Int) -> [Double] {
        let w = Swift.max(window, 1)
        var result: [Double] = []
        result.reserveCapacity(values.count)
        var sum = 0.0, n = 0
        for (i, v) in values.enumerated() {
            if v > 0 { sum += v; n += 1 }
            if i >= w {
                let old = values[i - w]
                if old > 0 { sum -= old; n -= 1 }
            }
            result.append(n > 0 ? sum / Double(n) : 0)
        }
        return result
    }

    /// Indices to keep so at most `maxPoints` remain: first, last and the min and max of every bucket in between.
    /// Extremes survive, so peaks are not smoothed away. Result is sorted and unique.
    public static func downsampleMinMax(_ values: [Double], maxPoints: Int) -> [Int] {
        let n = values.count
        guard n > maxPoints, maxPoints >= 4 else { return Array(0..<n) }
        let buckets = (maxPoints - 2) / 2
        let inner = n - 2
        var keep: Set<Int> = [0, n - 1]
        for b in 0..<buckets {
            let from = 1 + b * inner / buckets
            let to = 1 + (b + 1) * inner / buckets
            guard from < to else { continue }
            var lo = from, hi = from
            for i in from..<to {
                if values[i] < values[lo] { lo = i }
                if values[i] > values[hi] { hi = i }
            }
            keep.insert(lo); keep.insert(hi)
        }
        return keep.sorted()
    }

    // MARK: Gaps and selection

    /// Index ranges of consecutive (sorted) dates; a new range starts where the gap exceeds `gap` seconds.
    /// Each range becomes its own chart series, so the line is not interpolated across the gap.
    public static func segments(_ dates: [Date], splitWhenGapExceeds gap: TimeInterval) -> [Range<Int>] {
        guard !dates.isEmpty else { return [] }
        var result: [Range<Int>] = []
        var start = 0
        for i in 1..<Swift.max(dates.count, 1) where dates[i].timeIntervalSince(dates[i - 1]) > gap {
            result.append(start..<i)
            start = i
        }
        result.append(start..<dates.count)
        return result
    }

    /// Index of the date closest to `target` (for tap/drag selection).
    public static func nearest(_ dates: [Date], to target: Date) -> Int? {
        dates.indices.min { abs(dates[$0].timeIntervalSince(target)) < abs(dates[$1].timeIntervalSince(target)) }
    }

    /// Index of the value closest to `target` (e.g. snapping to measured power-curve durations).
    public static func nearest(_ values: [Double], to target: Double) -> Int? {
        values.indices.min { abs(values[$0] - target) < abs(values[$1] - target) }
    }

    // MARK: Words (German)

    /// German number text (decimal comma), no grouping.
    public static func format(_ value: Double, decimals: Int = 0) -> String {
        let f = NumberFormatter()
        f.locale = Locale.de
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.minimumFractionDigits = decimals
        f.maximumFractionDigits = decimals
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// One VoiceOver sentence for a time series: last value, trend against the first value, extremes.
    /// "Fitness 38, plus 3 in 7 Tagen. Höchstwert 40, Tiefstwert 31."
    public static func seriesSentence(name: String, values: [Double], decimals: Int = 0, unit: String = "",
                                      period: String? = nil) -> String {
        let v = values.filter(\.isFinite)
        guard let last = v.last, let first = v.first, let hi = v.max(), let lo = v.min() else { return "\(name): keine Daten." }
        var text = "\(name) \(format(last, decimals: decimals))\(unit)"
        if v.count > 1 {
            let delta = last - first
            let shown = format(abs(delta), decimals: decimals)
            let flat = Double(shown.replacingOccurrences(of: ",", with: ".")) == 0
            let trend = flat ? "unverändert" : "\(delta > 0 ? "plus" : "minus") \(shown)\(unit)"
            text += ", " + trend + (period.map { flat ? "" : " in \($0)" } ?? "")
        }
        text += "."
        if v.count > 2 {
            text += " Höchstwert \(format(hi, decimals: decimals))\(unit), Tiefstwert \(format(lo, decimals: decimals))\(unit)."
        }
        return text
    }
}
