import Foundation

/// Result of adjusting a workout: the new definition plus a short German description for banners and notes.
public struct WorkoutAdjustment: Equatable, Sendable {
    public var definition: WorkoutDefinition
    public var description: String
    /// False when the requested duration could not be reached within ±1 min (closest feasible result).
    public var isExact: Bool
}

/// Pure functions that make a planned workout shorter and/or easier. Always derived from the original definition.
public enum WorkoutAdjust {
    public static let shortenTargets = [30, 45, 60]
    static let minWarmCool = 300
    static let minFiller = 300
    static let fillerPower = 0.75

    /// Durations (min) that are at least 5 min shorter than the workout.
    public static func shortenOptions(for d: WorkoutDefinition) -> [Int] {
        shortenTargets.filter { d.totalDuration - $0 * 60 >= 300 }
    }

    public static func minutes(_ seconds: Int) -> Int { Int((Double(seconds) / 60).rounded()) }

    /// Combines shortening and easing; nil when nothing would change.
    public static func apply(to d: WorkoutDefinition, minutes: Int?, easierBy percent: Int?) -> WorkoutAdjustment? {
        var result = d
        var parts: [String] = []
        var exact = true
        if let minutes, d.totalDuration - minutes * 60 >= 300 {
            let (shorter, ok) = shortened(d, to: minutes)
            result = shorter
            exact = ok
            parts.append("\(Self.minutes(shorter.totalDuration)) min statt \(Self.minutes(d.totalDuration)) min")
        }
        if let percent, percent > 0 {
            result = easier(result, by: percent)
            parts.append("−\(percent)\u{00A0}% Intensität")   // no line break between number and %
        }
        guard !parts.isEmpty else { return nil }
        return WorkoutAdjustment(definition: result, description: parts.joined(separator: " · "), isExact: exact)
    }

    // MARK: Easier

    public static func easier(_ d: WorkoutDefinition, by percent: Int) -> WorkoutDefinition {
        let f = 1 - Double(percent) / 100
        func scale(_ v: Double?) -> Double? { v.map { ($0 * f * 10_000).rounded() / 10_000 } }
        var out = d
        out.segments = d.segments.map { s in
            var s = s
            s.power = scale(s.power); s.powerLow = scale(s.powerLow); s.powerHigh = scale(s.powerHigh); s.onPower = scale(s.onPower)
            return s
        }
        return out
    }

    // MARK: Shorter

    static func isFiller(_ s: Segment) -> Bool {
        (s.kind == .steady && (s.power ?? 0.6) < fillerPower) || s.kind == .freeRide
    }

    /// Returns the shortened definition and whether the target (±1 min) was reached.
    static func shortened(_ d: WorkoutDefinition, to minutes: Int) -> (WorkoutDefinition, Bool) {
        var segs = d.segments
        let target = minutes * 60
        func total() -> Int { segs.reduce(0) { $0 + $1.effectiveDuration } }
        func excess() -> Int { total() - target }
        let lastIndex = segs.count - 1
        func isWarm(_ i: Int) -> Bool { i == 0 && segs[i].kind == .warmup }
        func isCool(_ i: Int) -> Bool { i == lastIndex && segs[i].kind == .cooldown }
        let mainIdx = segs.indices.filter { !isWarm($0) && !isCool($0) }
        let original = segs

        // 1. Filler blocks (endurance / free ride), down to 5 min each.
        for i in mainIdx where excess() > 0 && isFiller(segs[i]) {
            let room = max(0, segs[i].duration - minFiller)
            segs[i].duration -= min(room, excess())
        }
        // 2. Interval repeats, never below 1; take from the block with the most repeats first.
        while excess() > 0 {
            let candidates = mainIdx.filter { segs[$0].kind == .intervals && (segs[$0].repeatCount ?? 1) > 1 }
            guard let i = candidates.max(by: { (segs[$0].repeatCount ?? 1) < (segs[$1].repeatCount ?? 1) }) else { break }
            let cycle = (segs[i].onDuration ?? 0) + (segs[i].offDuration ?? 0)
            guard cycle > 0, excess() >= cycle - 60 else { break }
            segs[i].repeatCount = (segs[i].repeatCount ?? 1) - 1
            segs[i].duration = segs[i].effectiveDuration
        }
        // 3. Remaining plain main blocks proportionally, never below 50 % of the original length.
        if excess() > 0 {
            let shrinkable = mainIdx.filter { [.steady, .ramp].contains(segs[$0].kind) && !isFiller(segs[$0]) }
            let room = shrinkable.map { max(0, segs[$0].duration - original[$0].duration / 2) }
            let roomSum = room.reduce(0, +)
            if roomSum > 0 {
                let take = min(excess(), roomSum)
                for (n, i) in shrinkable.enumerated() {
                    segs[i].duration -= Int((Double(room[n]) * Double(take) / Double(roomSum)).rounded())
                }
            }
        }
        // 4. Warm-up / cool-down, down to 5 min each.
        if excess() > 0 {
            let idx = segs.indices.filter { isWarm($0) || isCool($0) }
            let room = idx.map { max(0, segs[$0].duration - minWarmCool) }
            let roomSum = room.reduce(0, +)
            if roomSum > 0 {
                let take = min(excess(), roomSum)
                for (n, i) in idx.enumerated() {
                    segs[i].duration -= Int((Double(room[n]) * Double(take) / Double(roomSum)).rounded())
                }
            }
        }
        // 5. Rounding leftovers (a few seconds either way): nudge one plain block so the target is hit exactly.
        let rest = excess()
        if rest != 0, abs(rest) < 60,
           let i = segs.indices.first(where: { j in
               let floor = (isWarm(j) || isCool(j)) ? minWarmCool : (segs[j].kind == .intervals ? Int.max : original[j].duration / 2)
               let ok = [.steady, .ramp, .warmup, .cooldown, .freeRide].contains(segs[j].kind)
               return ok && segs[j].duration - rest >= floor && segs[j].duration - rest <= original[j].duration
           }) {
            segs[i].duration -= rest
        }
        var out = d
        out.segments = segs
        return (out, abs(excess()) <= 60)
    }
}
