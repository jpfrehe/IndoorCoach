import Foundation

/// A recording as stored on disk (in-progress file) or in the "waits for a ride" list. `RecordingResult` itself is the
/// contract type and not Codable, so this is its persistent twin. Heart rate is one byte per second (0 = gap).
public struct StoredRecording: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: RecordingKind
    public var title: String
    public var startedAt: Date
    public var endedAt: Date
    public var heartRate: Data
    public var gapSeconds: Int
    public var reconnects: Int
    public var plannedWorkoutID: UUID?
    /// Plan the recording follows (for the timeline after a resume); nil without plan.
    public var definition: WorkoutDefinition?

    public init(id: UUID, kind: RecordingKind, title: String, startedAt: Date, endedAt: Date, heartRate: Data,
                gapSeconds: Int, reconnects: Int, plannedWorkoutID: UUID?, definition: WorkoutDefinition? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.heartRate = heartRate
        self.gapSeconds = gapSeconds
        self.reconnects = reconnects
        self.plannedWorkoutID = plannedWorkoutID
        self.definition = definition
    }

    public init(_ result: RecordingResult, definition: WorkoutDefinition? = nil) {
        self.init(id: result.id, kind: result.kind, title: result.title, startedAt: result.startedAt, endedAt: result.endedAt,
                  heartRate: Data(result.seconds.heartRate ?? []), gapSeconds: result.gapSeconds, reconnects: result.reconnects,
                  plannedWorkoutID: result.plannedWorkoutID, definition: definition)
    }

    public var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
    public var heartRateSeconds: [UInt8] { [UInt8](heartRate) }

    public var result: RecordingResult {
        let hr = heartRateSeconds
        return RecordingResult(id: id, kind: kind, title: title, startedAt: startedAt, endedAt: endedAt,
                               seconds: RideSeconds(power: [UInt16](repeating: 0, count: hr.count), heartRate: hr),
                               gapSeconds: gapSeconds, reconnects: reconnects, plannedWorkoutID: plannedWorkoutID)
    }
}

/// Pure logic to hang a pulse-only recording on a ride (B40).
public enum RecordingMerge {
    /// Ride start within this window of the recording start.
    public static let matchWindow: TimeInterval = 30 * 60
    /// The search for the pulse rise looks this far around the planned time (seconds).
    public static let maxFineShift = 90
    /// The pulse reacts to a power step with this delay; the detected rise centre is that much later than the step.
    static let responseDelay = 40
    static let riseWindow = 45
    static let minRise = 6.0

    // MARK: Matching

    /// The indoor ride that best fits the recording: start within ±30 min, similar duration; nearest start wins.
    public static func bestMatch(for recording: StoredRecording, in rides: [RideSummary]) -> RideSummary? {
        let duration = recording.duration
        func gap(_ r: RideSummary) -> TimeInterval { abs(r.startDate.timeIntervalSince(recording.startedAt)) }
        func similar(_ r: RideSummary) -> Bool {
            let d = Double(r.movingTime)
            return abs(d - duration) <= 600 || (duration > 0 && d / duration >= 0.6 && d / duration <= 1.5)
        }
        return rides.filter { $0.isIndoor && gap($0) <= matchWindow && similar($0) }.min { gap($0) < gap($1) }
    }

    // MARK: Alignment

    /// Seconds to skip at the beginning of the recording so that index 0 is the ride start (negative: pad in front).
    public static func baseShift(recording: StoredRecording, rideStart: Date) -> Int {
        Int(rideStart.timeIntervalSince(recording.startedAt).rounded())
    }

    /// `length` seconds of `hr` starting at `shift`; out-of-range seconds are 0 (gap).
    public static func align(_ hr: [UInt8], shift: Int, length: Int) -> [UInt8] {
        guard length > 0 else { return [] }
        return (0..<length).map { i in
            let j = i + shift
            return j >= 0 && j < hr.count ? hr[j] : 0
        }
    }

    /// Fine correction (seconds, added to the base shift): the planned power step at `expectedRiseAt` (end of the
    /// warm-up) shows up as the strongest pulse rise nearby. Returns 0 without a clear rise (< 6 bpm), limited to ±90 s.
    /// `hr` must already be on the ride timeline (base shift applied).
    public static func fineShift(hr: [UInt8], expectedRiseAt: Int) -> Int {
        guard !hr.isEmpty else { return 0 }
        func mean(_ range: Range<Int>) -> Double? {
            let lo = max(0, range.lowerBound), hi = min(hr.count, range.upperBound)
            guard lo < hi else { return nil }
            let valid = hr[lo..<hi].filter { $0 > 0 }
            return valid.count >= riseWindow / 2 ? Double(valid.reduce(0) { $0 + Int($1) }) / Double(valid.count) : nil
        }
        var best: (t: Int, score: Double)?
        let from = expectedRiseAt - maxFineShift + responseDelay
        let to = expectedRiseAt + maxFineShift + responseDelay
        for t in from...to {
            guard let after = mean(t..<(t + riseWindow)), let before = mean((t - riseWindow)..<t) else { continue }
            let score = after - before
            if score >= minRise, score > (best?.score ?? 0) { best = (t, score) }
        }
        guard let best else { return 0 }
        return min(maxFineShift, max(-maxFineShift, best.t - responseDelay - expectedRiseAt))
    }

    // MARK: Combining

    /// Real power exists (not just the zeros of a pulse-only recording).
    public static func hasPower(_ seconds: RideSeconds) -> Bool {
        seconds.power.reduce(0) { $0 + ($1 > 0 ? 1 : 0) } >= max(1, min(10, seconds.count / 10))
    }

    /// Pulse of the iPhone onto a ride's seconds: power is never touched, the existing pulse wins, the iPhone pulse
    /// only fills seconds without a value. `heartRate` is already aligned to the ride timeline.
    public static func merge(existing: RideSeconds?, heartRate: [UInt8]) -> RideSeconds {
        guard let existing else {
            return RideSeconds(power: [UInt16](repeating: 0, count: heartRate.count), heartRate: heartRate)
        }
        let phone = align(heartRate, shift: 0, length: existing.count)
        let own = existing.heartRate ?? [UInt8](repeating: 0, count: existing.count)
        let combined = zip(own, phone).map { $0 > 0 ? $0 : $1 }
        return RideSeconds(power: existing.power, heartRate: combined)
    }

    /// Incoming measured seconds (bridge / FIT) for a ride that may already carry a pulse-only recording:
    /// nil = keep the existing seconds (they have real power), otherwise the seconds to store (the iPhone pulse fills
    /// the gaps of the incoming pulse).
    public static func upgrade(existing: RideSeconds?, incoming: RideSeconds) -> RideSeconds? {
        guard let existing else { return incoming }
        if hasPower(existing) { return nil }
        guard let phone = existing.heartRate else { return incoming }
        let own = incoming.heartRate ?? [UInt8](repeating: 0, count: incoming.count)
        let aligned = align(phone, shift: 0, length: incoming.count)
        return RideSeconds(power: incoming.power, heartRate: zip(own, aligned).map { $0 > 0 ? $0 : $1 })
    }
}

/// ERG assumption: with a trainer in ERG mode the power equals the plan in steady blocks. Only blocks of at least two
/// minutes count; ramps and short intervals are not assessable. Assumed watts are never stored as power seconds and
/// never feed the power curve or planned-vs-actual.
public enum ERGAssumption {
    public static let minBlockSeconds = 120

    public struct Block: Equatable, Sendable {
        public var start: Int
        public var duration: Int
        public var watts: Int
        public init(start: Int, duration: Int, watts: Int) {
            self.start = start
            self.duration = duration
            self.watts = watts
        }
    }

    public struct Analysis: Equatable, Sendable {
        public var blocks: [Block]
        public var unassessableSeconds: Int
    }

    public static func analyze(definition: WorkoutDefinition, ftp: Int) -> Analysis {
        var blocks: [Block] = []
        var skipped = 0
        var t = 0
        func steady(_ duration: Int, _ fraction: Double) {
            if duration >= minBlockSeconds, ftp > 0 {
                blocks.append(Block(start: t, duration: duration, watts: Int((fraction * Double(ftp)).rounded())))
            } else {
                skipped += duration
            }
            t += duration
        }
        for s in definition.segments {
            switch s.kind {
            case .steady:
                steady(s.duration, s.power ?? 0.6)
            case .intervals:
                let n = max(0, s.repeatCount ?? 1), on = s.onDuration ?? 60, off = s.offDuration ?? 60
                for _ in 0..<n {
                    steady(on, s.onPower ?? 1.0)
                    if off > 0 { steady(off, s.offPower ?? 0.5) }
                }
            case .warmup, .ramp, .cooldown, .freeRide:
                skipped += s.effectiveDuration
                t += s.effectiveDuration
            }
        }
        return Analysis(blocks: blocks, unassessableSeconds: skipped)
    }

    /// Mean pulse per block (valid seconds only); nil when fewer than 30 valid seconds.
    public static func meanPulse(hr: [UInt8], blocks: [Block]) -> [Double?] {
        blocks.map { block in
            let lo = max(0, block.start), hi = min(hr.count, block.start + block.duration)
            guard lo < hi else { return nil }
            let valid = hr[lo..<hi].filter { $0 > 0 }
            return valid.count >= 30 ? Double(valid.reduce(0) { $0 + Int($1) }) / Double(valid.count) : nil
        }
    }
}
