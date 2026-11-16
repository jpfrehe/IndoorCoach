import Foundation

/// One building block of a structured indoor workout. Mirrors the `.zwo` element set so export is lossless.
/// Power values are fractions of FTP (1.0 = 100 % FTP).
public struct Segment: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case warmup, steady, ramp, intervals, cooldown, freeRide
    }

    public var id = UUID()
    public var kind: Kind
    /// Total duration in seconds. For `.intervals` this is derived from repeat × (on + off).
    public var duration: Int
    public var power: Double?
    public var powerLow: Double?
    public var powerHigh: Double?
    public var repeatCount: Int?
    public var onDuration: Int?
    public var offDuration: Int?
    public var onPower: Double?
    public var offPower: Double?
    public var cadence: Int?
    public var text: String?

    enum CodingKeys: String, CodingKey {
        case kind, duration, power, powerLow, powerHigh, repeatCount = "repeat", onDuration, offDuration
        case onPower, offPower, cadence, text
    }

    public init(kind: Kind, duration: Int, power: Double? = nil, powerLow: Double? = nil, powerHigh: Double? = nil,
                repeatCount: Int? = nil, onDuration: Int? = nil, offDuration: Int? = nil,
                onPower: Double? = nil, offPower: Double? = nil, cadence: Int? = nil, text: String? = nil) {
        self.kind = kind
        self.duration = duration
        self.power = power
        self.powerLow = powerLow
        self.powerHigh = powerHigh
        self.repeatCount = repeatCount
        self.onDuration = onDuration
        self.offDuration = offDuration
        self.onPower = onPower
        self.offPower = offPower
        self.cadence = cadence
        self.text = text
    }

    // MARK: Convenience factories

    public static func warmup(_ minutes: Double, from low: Double, to high: Double, text: String? = nil) -> Segment {
        Segment(kind: .warmup, duration: Int(minutes * 60), powerLow: low, powerHigh: high, text: text)
    }

    public static func steady(_ minutes: Double, at power: Double, cadence: Int? = nil, text: String? = nil) -> Segment {
        Segment(kind: .steady, duration: Int(minutes * 60), power: power, cadence: cadence, text: text)
    }

    public static func ramp(_ minutes: Double, from low: Double, to high: Double, text: String? = nil) -> Segment {
        Segment(kind: .ramp, duration: Int(minutes * 60), powerLow: low, powerHigh: high, text: text)
    }

    public static func intervals(_ count: Int, on: Int, at onPower: Double, off: Int, at offPower: Double,
                                 cadence: Int? = nil, text: String? = nil) -> Segment {
        Segment(kind: .intervals, duration: count * (on + off), repeatCount: count, onDuration: on, offDuration: off,
                onPower: onPower, offPower: offPower, cadence: cadence, text: text)
    }

    public static func cooldown(_ minutes: Double, from high: Double, to low: Double) -> Segment {
        Segment(kind: .cooldown, duration: Int(minutes * 60), powerLow: low, powerHigh: high)
    }

    public static func freeRide(_ minutes: Double, text: String? = nil) -> Segment {
        Segment(kind: .freeRide, duration: Int(minutes * 60), text: text)
    }

    /// Effective duration, recomputed for interval blocks so inconsistent LLM output cannot skew totals.
    public var effectiveDuration: Int {
        if kind == .intervals, let r = repeatCount, let on = onDuration, let off = offDuration {
            return r * (on + off)
        }
        return duration
    }
}

/// A flat step of the expanded workout – used for charts, TSS and the calendar text.
public struct PowerStep: Hashable, Sendable {
    public var start: Int      // seconds from workout start
    public var duration: Int   // seconds
    public var startPower: Double
    public var endPower: Double
    public var isRecovery: Bool

    public var averagePower: Double { (startPower + endPower) / 2 }
}

public enum WorkoutType: String, Codable, Sendable, CaseIterable, Identifiable {
    case recovery, endurance, tempo, sweetSpot, threshold, vo2max, anaerobic, sprint, test, mixed

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .recovery: "Regeneration"
        case .endurance: "Grundlage"
        case .tempo: "Tempo"
        case .sweetSpot: "Sweet Spot"
        case .threshold: "Schwelle"
        case .vo2max: "VO₂max"
        case .anaerobic: "Anaerob"
        case .sprint: "Sprint"
        case .test: "Test"
        case .mixed: "Gemischt"
        }
    }

    public var symbol: String {
        switch self {
        case .recovery: "leaf"
        case .endurance: "road.lanes"
        case .tempo: "metronome"
        case .sweetSpot: "target"
        case .threshold: "gauge.with.dots.needle.67percent"
        case .vo2max: "lungs"
        case .anaerobic: "flame"
        case .sprint: "bolt"
        case .test: "stopwatch"
        case .mixed: "square.stack.3d.up"
        }
    }
}

/// Value type describing a structured workout (independent of persistence).
public struct WorkoutDefinition: Codable, Hashable, Sendable {
    public var title: String
    public var type: WorkoutType
    public var summary: String
    public var segments: [Segment]

    public init(title: String, type: WorkoutType, summary: String, segments: [Segment]) {
        self.title = title
        self.type = type
        self.summary = summary
        self.segments = segments
    }

    public var totalDuration: Int { segments.reduce(0) { $0 + $1.effectiveDuration } }

    /// Expands segments into steps (intervals unrolled). Free ride is modelled as 55 % FTP.
    public var steps: [PowerStep] {
        var result: [PowerStep] = []
        var t = 0
        for s in segments {
            switch s.kind {
            case .steady:
                let p = s.power ?? 0.6
                result.append(PowerStep(start: t, duration: s.duration, startPower: p, endPower: p, isRecovery: false))
                t += s.duration
            case .warmup, .ramp:
                let lo = s.powerLow ?? 0.45, hi = s.powerHigh ?? 0.75
                result.append(PowerStep(start: t, duration: s.duration, startPower: lo, endPower: hi, isRecovery: false))
                t += s.duration
            case .cooldown:
                // Cooldown goes from high to low.
                let lo = s.powerLow ?? 0.4, hi = s.powerHigh ?? 0.65
                result.append(PowerStep(start: t, duration: s.duration, startPower: hi, endPower: lo, isRecovery: true))
                t += s.duration
            case .freeRide:
                result.append(PowerStep(start: t, duration: s.duration, startPower: 0.55, endPower: 0.55, isRecovery: true))
                t += s.duration
            case .intervals:
                let n = s.repeatCount ?? 1, on = s.onDuration ?? 60, off = s.offDuration ?? 60
                let pOn = s.onPower ?? 1.0, pOff = s.offPower ?? 0.5
                for _ in 0..<max(n, 0) {
                    result.append(PowerStep(start: t, duration: on, startPower: pOn, endPower: pOn, isRecovery: false))
                    t += on
                    if off > 0 {
                        result.append(PowerStep(start: t, duration: off, startPower: pOff, endPower: pOff, isRecovery: true))
                        t += off
                    }
                }
            }
        }
        return result
    }

    /// Normalized-power style intensity factor estimated from the planned steps (4th-power mean, 30 s resolution).
    public var intensityFactor: Double {
        let total = totalDuration
        guard total > 0 else { return 0 }
        var sum4 = 0.0
        for step in steps where step.duration > 0 {
            // Integrate the 4th power over linear ramps with a small Riemann sum.
            let slices = max(1, step.duration / 30)
            let sliceDur = Double(step.duration) / Double(slices)
            for i in 0..<slices {
                let frac = (Double(i) + 0.5) / Double(slices)
                let p = step.startPower + (step.endPower - step.startPower) * frac
                sum4 += pow(p, 4) * sliceDur
            }
        }
        return pow(sum4 / Double(total), 0.25)
    }

    /// Planned TSS = hours × IF² × 100.
    public var estimatedTSS: Double {
        let hours = Double(totalDuration) / 3600
        return hours * intensityFactor * intensityFactor * 100
    }

    /// Time spent per power zone (seconds), using step averages.
    public func timeInZones() -> [PowerZone: Int] {
        var result: [PowerZone: Int] = [:]
        for step in steps {
            result[PowerZone(fractionOfFTP: step.averagePower), default: 0] += step.duration
        }
        return result
    }

    /// Plain-text description used for calendar notes.
    public func plainTextDescription(ftp: Int) -> String {
        segments.map { "• " + $0.describe(ftp: ftp) }.joined(separator: "\n")
    }
}

extension Segment {
    public func describe(ftp: Int) -> String {
        func w(_ f: Double?) -> String { "\(Int(((f ?? 0) * Double(ftp)).rounded())) W" }
        func pct(_ f: Double?) -> String { "\(Int(((f ?? 0) * 100).rounded())) %" }
        let base: String
        switch kind {
        case .warmup:
            base = "Einfahren \(Formatters.duration(duration)): \(pct(powerLow)) → \(pct(powerHigh)) (\(w(powerLow))–\(w(powerHigh)))"
        case .steady:
            base = "\(Formatters.duration(duration)) @ \(pct(power)) (\(w(power)))"
        case .ramp:
            base = "Rampe \(Formatters.duration(duration)): \(pct(powerLow)) → \(pct(powerHigh))"
        case .intervals:
            base = "\(repeatCount ?? 1)× \(Formatters.duration(onDuration ?? 0)) @ \(pct(onPower)) (\(w(onPower))) / \(Formatters.duration(offDuration ?? 0)) @ \(pct(offPower))"
        case .cooldown:
            base = "Ausfahren \(Formatters.duration(duration)): \(pct(powerHigh)) → \(pct(powerLow))"
        case .freeRide:
            base = "Frei fahren \(Formatters.duration(duration))"
        }
        var extras: [String] = []
        if let cadence { extras.append("\(cadence) rpm") }
        if let text, !text.isEmpty { extras.append(text) }
        return extras.isEmpty ? base : base + " – " + extras.joined(separator: ", ")
    }
}
