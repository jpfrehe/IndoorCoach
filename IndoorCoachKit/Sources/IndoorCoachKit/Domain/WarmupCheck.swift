import Foundation

/// "Aufwärm-Check": every warm-up carries a standard block (6 min steady at a fixed reference power). The mean heart
/// rate of its last 60 s, measured at the same watts again and again, shows progress as a falling pulse. It is a
/// comparison point only – never a statement about fatigue on its own.
public struct WarmupCheck: Equatable, Sendable {
    public enum Source: String, Sendable {
        /// Power seconds exist and confirm the reference power.
        case measured
        /// No power seconds (only pulse + plan): the trainer in ERG mode is assumed to have held the reference.
        case assumedERG
    }

    public var date: Date
    public var refWatts: Int
    /// Mean pulse of the last 60 s of the block (valid seconds only); nil when it cannot be determined.
    public var hrMean: Double?
    public var valid: Bool
    /// Why the check is not valid (German, shown to the athlete); nil when valid.
    public var reason: String?
    public var source: Source

    public init(date: Date, refWatts: Int, hrMean: Double?, valid: Bool, reason: String?, source: Source) {
        self.date = date
        self.refWatts = refWatts
        self.hrMean = hrMean
        self.valid = valid
        self.reason = reason
        self.source = source
    }

    // MARK: Parameters

    public static let markerText = "Aufwärm-Check"
    public static let blockSeconds = 360
    public static let blockCadence = 90
    /// Share of FTP used when the athlete has no reference yet.
    public static let defaultFraction = 0.55
    /// Allowed deviation of the mean power from the reference.
    public static let powerTolerance = 0.05
    /// Window at the end of the block whose pulse counts.
    public static let evaluationWindow = 60
    /// At least this many seconds of the window need a plausible pulse.
    public static let minValidPulseSeconds = 50
    /// Pulse change between consecutive seconds above which the signal is treated as faulty (bpm).
    public static let maxPulseStep = 10.0
    /// First seconds of the block (power ramps in, pulse follows) not used for the power check.
    static let rampIn = 60
    /// Fallback search: block must start within this many seconds and be at least this long.
    static let fallbackStartLimit = 900
    static let fallbackMinSeconds = 300
    /// Trend: minimum valid measurements, change (bpm) at which the median counts as moved.
    public static let minChecksForTrend = 3
    public static let trendThreshold = 2.0

    // MARK: Reference

    /// 55 % of FTP, rounded to 5 W.
    public static func defaultWatts(ftp: Int) -> Int {
        guard ftp > 0 else { return 0 }
        return Int((Double(ftp) * defaultFraction / 5).rounded()) * 5
    }

    /// Reference power as a fraction of FTP (what the plan segments use).
    public static func fraction(refWatts: Int, ftp: Int) -> Double {
        ftp > 0 ? Double(refWatts) / Double(ftp) : defaultFraction
    }

    // MARK: Block in the plan

    static func isBlock(_ s: Segment) -> Bool {
        s.kind == .steady && s.text?.localizedCaseInsensitiveContains(markerText) == true
    }

    static func standardBlock(refWatts: Int, ftp: Int) -> Segment {
        let fraction = (fraction(refWatts: refWatts, ftp: ftp) * 100).rounded() / 100
        return Segment(kind: .steady, duration: blockSeconds, power: fraction, cadence: blockCadence, text: markerText)
    }

    /// Makes sure a workout with a warm-up carries exactly the standard block right behind the first warm-up segment:
    /// an existing (possibly altered) block is normalised in place, a missing one is inserted. Workouts without
    /// warm-up stay untouched.
    public static func ensuringBlock(in segments: [Segment], refWatts: Int, ftp: Int) -> [Segment] {
        guard refWatts > 0, ftp > 0 else { return segments }
        var result = segments
        let block = standardBlock(refWatts: refWatts, ftp: ftp)
        if let i = result.firstIndex(where: isBlock) {
            var normalized = block
            normalized.id = result[i].id
            result[i] = normalized
            return result
        }
        guard let w = result.firstIndex(where: { $0.kind == .warmup }) else { return segments }
        result.insert(block, at: w + 1)
        return result
    }

    /// Start (seconds on the plan timeline) of the block; nil when the workout has none.
    public static func blockStart(in definition: WorkoutDefinition) -> Int? {
        var t = 0
        for s in definition.segments {
            if isBlock(s) { return t }
            t += s.effectiveDuration
        }
        return nil
    }

    // MARK: Evaluation

    /// Evaluates the check of one ride. `definition` is the linked planned workout (if any). Returns nil when no
    /// block can be located; an invalid check (with reason) when it was located but is not usable.
    public static func evaluate(date: Date, definition: WorkoutDefinition?, seconds: RideSeconds,
                                ftp: Int, refWatts: Int) -> WarmupCheck? {
        guard refWatts > 0, ftp > 0 else { return nil }
        let hasPower = seconds.hasPower

        if let definition, let planned = blockStart(in: definition) {
            if hasPower {
                let offset = alignmentOffset(definition: definition, seconds: seconds, ftp: ftp)
                return judge(date: date, from: offset + planned, seconds: seconds, refWatts: refWatts, source: .measured)
            }
            return judge(date: date, from: planned, seconds: seconds, refWatts: refWatts, source: .assumedERG)
        }
        guard hasPower, let start = steadyStretch(in: seconds.watts, refWatts: refWatts) else { return nil }
        return judge(date: date, from: start, seconds: seconds, refWatts: refWatts, source: .measured)
    }

    private static func alignmentOffset(definition: WorkoutDefinition, seconds: RideSeconds, ftp: Int) -> Int {
        let steps = definition.steps
        let total = steps.reduce(0) { max($0, $1.start + $1.duration) }
        guard total > 0, seconds.count >= 60 else { return 0 }
        var target = [Double](repeating: 0, count: total)
        for step in steps where step.duration > 0 {
            for i in 0..<step.duration where step.start + i < total {
                let frac = step.startPower + (step.endPower - step.startPower) * (Double(i) + 0.5) / Double(step.duration)
                target[step.start + i] = frac * Double(ftp)
            }
        }
        return IntervalCompliance.bestOffset(target: target, actual: IntervalCompliance.smoothed(seconds.watts, window: 30))
    }

    /// First start (within the first 15 min) from which the trailing 30-s power stays within tolerance of the reference
    /// for at least 5 min (after a 60-s ramp-in). Block length is capped at the standard 6 min.
    private static func steadyStretch(in watts: [Double], refWatts: Int) -> Int? {
        let n = watts.count
        guard n >= fallbackMinSeconds + 30 else { return nil }
        var prefix = [Double](repeating: 0, count: n + 1)
        for i in 0..<n { prefix[i + 1] = prefix[i] + watts[i] }
        let ref = Double(refWatts)
        func holds(_ i: Int) -> Bool {   // trailing 30-s mean ending before second i
            guard i >= 30, i <= n else { return false }
            return abs((prefix[i] - prefix[i - 30]) / 30 - ref) <= powerTolerance * ref
        }
        for start in stride(from: 0, through: min(fallbackStartLimit, n - fallbackMinSeconds), by: 5) {
            guard (start + rampIn...start + fallbackMinSeconds).allSatisfy(holds) else { continue }
            return start
        }
        return nil
    }

    /// Checks power and pulse of the block starting at `from` and builds the result.
    private static func judge(date: Date, from: Int, seconds: RideSeconds, refWatts: Int, source: Source) -> WarmupCheck {
        func result(_ hr: Double?, _ reason: String?) -> WarmupCheck {
            WarmupCheck(date: date, refWatts: refWatts, hrMean: reason == nil ? hr : nil, valid: reason == nil,
                        reason: reason, source: source)
        }
        let end = from + blockSeconds
        guard from >= 0, end <= seconds.count else { return result(nil, "Die Fahrt endet vor dem Ende des Aufwärm-Checks.") }

        if source == .measured {
            let block = seconds.power[(from + rampIn)..<end]
            let mean = block.reduce(0) { $0 + Double($1) } / Double(block.count)
            if abs(mean - Double(refWatts)) > powerTolerance * Double(refWatts) {
                return result(nil, "Die Leistung lag im Block bei \(Int(mean.rounded())) W statt \(refWatts) W.")
            }
        }
        guard let heart = seconds.heartRate else { return result(nil, "Kein Puls in den Sekundendaten.") }
        let window = heart[(end - evaluationWindow)..<end]
        let valid = window.filter { $0 > 0 }
        guard valid.count >= minValidPulseSeconds else { return result(nil, "Der Puls hat in der letzten Minute ausgesetzt.") }
        var previous: UInt8?
        for bpm in window {
            if bpm == 0 { continue }
            if let p = previous, abs(Double(bpm) - Double(p)) > maxPulseStep {
                return result(nil, "Der Puls hat in der letzten Minute gesprungen.")
            }
            previous = bpm
        }
        return result(valid.reduce(0) { $0 + Double($1) } / Double(valid.count), nil)
    }

    // MARK: Trend

    public struct Trend: Equatable, Sendable {
        public enum Direction: String, Sendable { case notEnough, falling, stable, rising }

        public var refWatts: Int
        /// Valid measurements at this reference power.
        public var count: Int
        /// Median of the last three valid measurements.
        public var medianHR: Double?
        public var direction: Direction
        /// Newer minus older half (bpm), nil without a trend.
        public var delta: Double?
        /// True when all counted measurements are `.measured`.
        public var allMeasured: Bool
    }

    /// Median-based trend of the valid checks at `refWatts` (optionally only since a baseline date). From
    /// `minChecksForTrend` measurements the median of the older half is compared with the newer half.
    /// `source` beschränkt den Trend auf gemessene oder auf angenommene (ERG) Werte; `nil` = alle (nur zur Anzeige).
    public static func trend(checks: [WarmupCheck], refWatts: Int, since: Date? = nil, source: Source? = nil) -> Trend {
        let used = checks
            .filter { check in
                check.valid && check.hrMean != nil && check.refWatts == refWatts && (since.map { check.date >= $0 } ?? true)
                    && (source.map { check.source == $0 } ?? true)
            }
            .sorted { $0.date < $1.date }
        let values = used.compactMap(\.hrMean)
        let allMeasured = used.allSatisfy { $0.source == .measured }
        let latest = median(Array(values.suffix(3)))
        guard values.count >= minChecksForTrend else {
            return Trend(refWatts: refWatts, count: values.count, medianHR: latest, direction: .notEnough, delta: nil, allMeasured: allMeasured)
        }
        let half = values.count / 2
        let delta = (median(Array(values.suffix(half))) ?? 0) - (median(Array(values.prefix(half))) ?? 0)
        let direction: Trend.Direction = delta <= -trendThreshold ? .falling : (delta >= trendThreshold ? .rising : .stable)
        return Trend(refWatts: refWatts, count: values.count, medianHR: latest, direction: direction, delta: delta, allMeasured: allMeasured)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}
