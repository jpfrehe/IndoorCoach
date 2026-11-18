import Foundation

/// Planned vs. actual per work interval: the workout's target profile (fraction of FTP) is laid onto the 1 Hz power
/// of the linked ride; the start offset is found by minimising the error against the 30-s-smoothed power.
public enum IntervalCompliance {
    public enum Status: String, Sendable, Equatable {
        case hit, under, over, missed
    }

    public struct Interval: Equatable, Sendable, Identifiable {
        public var id: Int { index }
        /// 1-based.
        public var index: Int
        /// Seconds from the workout start (plan timeline).
        public var start: Int
        public var duration: Int
        public var targetWatts: Int
        /// Average over the interval without the first 10 s; nil when `.missed`.
        public var actualWatts: Double?
        /// (actual − target) / target; −1 when missed.
        public var deviation: Double
        public var status: Status
        /// 0…100, 0 when missed.
        public var compliance: Double
    }

    public struct Result: Equatable, Sendable {
        /// Seconds the ride started before the plan (0…600).
        public var offset: Int
        public var intervals: [Interval]
        /// True when the workout has no work intervals; `intervals` then holds the single block "Grundlage".
        public var isBaseline: Bool
        /// Per second of the plan timeline: target watts, and the 30-s-smoothed actual watts (shorter when the ride ends early).
        public var targetSeries: [Double]
        public var actualSeries: [Double]

        public var total: Int { intervals.count }
        public var hitCount: Int { intervals.filter { $0.status == .hit }.count }
        public var averageCompliance: Double {
            intervals.isEmpty ? 0 : intervals.reduce(0) { $0 + $1.compliance } / Double(intervals.count)
        }

        public var summary: String {
            if isBaseline, let block = intervals.first {
                guard let actual = block.actualWatts else { return "Grundlage: keine Daten" }
                return "Grundlage: Ø \(Int(actual.rounded())) W bei \(block.targetWatts) W Soll · \(Int(block.compliance.rounded())) %"
            }
            return "\(hitCount) von \(total) Intervallen getroffen · Ø \(Int(averageCompliance.rounded())) %"
        }
    }

    public static let tolerance = 0.05
    public static let workThreshold = 0.75
    static let rampIn = 10
    static let maxOffset = 600

    public static func analyze(definition: WorkoutDefinition, seconds: RideSeconds, ftp: Int) -> Result? {
        let steps = definition.steps
        let total = steps.reduce(0) { max($0, $1.start + $1.duration) }
        guard total > 0, ftp > 0, seconds.count >= 60 else { return nil }
        let f = Double(ftp)

        var target = [Double](repeating: 0, count: total)
        for step in steps where step.duration > 0 {
            for i in 0..<step.duration where step.start + i < total {
                let frac = step.startPower + (step.endPower - step.startPower) * (Double(i) + 0.5) / Double(step.duration)
                target[step.start + i] = frac * f
            }
        }

        let raw = seconds.watts
        let smooth = smoothed(raw, window: 30)
        let offset = bestOffset(target: target, actual: smooth)

        let blocks = workBlocks(definition)
        let isBaseline = blocks.isEmpty
        let ranges = isBaseline ? [(start: 0, duration: total, fraction: target.reduce(0, +) / Double(total) / f)] : blocks

        var intervals: [Interval] = []
        for (n, block) in ranges.enumerated() {
            let targetW = Int((block.fraction * f).rounded())
            let from = offset + block.start + (isBaseline ? 0 : rampIn)
            let to = min(offset + block.start + block.duration, raw.count)
            let needed = max(20, (block.duration - (isBaseline ? 0 : rampIn)) / 2)
            guard to - from >= needed, targetW > 0 else {
                intervals.append(Interval(index: n + 1, start: block.start, duration: block.duration, targetWatts: targetW,
                                          actualWatts: nil, deviation: -1, status: .missed, compliance: 0))
                continue
            }
            let actual = raw[from..<to].reduce(0, +) / Double(to - from)
            let deviation = (actual - Double(targetW)) / Double(targetW)
            let status: Status = abs(deviation) <= tolerance ? .hit : (deviation < 0 ? .under : .over)
            intervals.append(Interval(index: n + 1, start: block.start, duration: block.duration, targetWatts: targetW,
                                      actualWatts: actual, deviation: deviation, status: status,
                                      compliance: max(0, 100 - abs(deviation) * 100)))
        }

        let available = max(0, min(total, smooth.count - offset))
        let actualSeries = available > 0 ? Array(smooth[offset..<(offset + available)]) : []
        return Result(offset: offset, intervals: intervals, isBaseline: isBaseline, targetSeries: target, actualSeries: actualSeries)
    }

    // MARK: Work blocks

    /// Steady segments and interval "on" parts with a target of at least 75 % FTP, on the plan timeline.
    static func workBlocks(_ definition: WorkoutDefinition) -> [(start: Int, duration: Int, fraction: Double)] {
        var blocks: [(start: Int, duration: Int, fraction: Double)] = []
        var t = 0
        for s in definition.segments {
            switch s.kind {
            case .steady:
                let p = s.power ?? 0.6
                if p >= workThreshold, s.duration > 0 { blocks.append((t, s.duration, p)) }
                t += s.duration
            case .intervals:
                let n = s.repeatCount ?? 1, on = s.onDuration ?? 60, off = s.offDuration ?? 60
                let pOn = s.onPower ?? 1.0
                for _ in 0..<max(n, 0) {
                    if pOn >= workThreshold, on > 0 { blocks.append((t, on, pOn)) }
                    t += on + max(off, 0)
                }
            default:
                t += s.duration
            }
        }
        return blocks
    }

    // MARK: Alignment

    /// Centered moving average (prefix sums, O(n)).
    static func smoothed(_ x: [Double], window: Int) -> [Double] {
        let n = x.count
        guard n > 0 else { return [] }
        var prefix = [Double](repeating: 0, count: n + 1)
        for i in 0..<n { prefix[i + 1] = prefix[i] + x[i] }
        let before = window / 2, after = window / 2 + 1   // symmetric around i (31 samples)
        return (0..<n).map { i in
            let lo = max(0, i - before), hi = min(n, i + after)
            return (prefix[hi] - prefix[lo]) / Double(hi - lo)
        }
    }

    /// Start offset 0…600 s (ride started earlier than the plan) with the least mean squared error; coarse 5 s, then 1 s.
    static func bestOffset(target: [Double], actual: [Double]) -> Int {
        let span = min(target.count, 5400)
        let maxO = min(maxOffset, actual.count - 60)
        guard maxO > 0, span > 0 else { return 0 }
        func error(_ o: Int) -> Double {
            let n = min(span, actual.count - o)
            guard n >= 60 else { return .infinity }
            var sum = 0.0
            for t in 0..<n {
                let d = target[t] - actual[t + o]
                sum += d * d
            }
            return sum / Double(n)
        }
        var best = 0, bestError = error(0)
        for o in stride(from: 5, through: maxO, by: 5) {
            let e = error(o)
            if e < bestError { best = o; bestError = e }
        }
        for o in max(0, best - 4)...min(maxO, best + 4) {
            let e = error(o)
            if e < bestError { best = o; bestError = e }
        }
        return best
    }
}
