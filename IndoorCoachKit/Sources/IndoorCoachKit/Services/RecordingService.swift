import Foundation
import Observation

// B37: recording of a workout with the heart-rate strap on the iPhone. Collects the strap's pulse values into a 1 Hz
// track, saves it every 30 s, tells the lock screen what is going on and hands a `RecordingResult` to the consumer.
// Nothing here talks to Bluetooth directly: `StrapSession` is the source, tests feed `ingest(...)`.

// MARK: - Plan timeline

/// One block of the planned workout on the recording timeline (seconds since the start).
public struct PlanBlock: Equatable, Sendable, Identifiable {
    public var id: Int { start }
    public var title: String
    public var start: Int
    public var duration: Int
    /// Target in fractions of FTP (mean for ramps); nil without target.
    public var fraction: Double?
    public var end: Int { start + duration }
}

public enum RecordingPlan {
    /// Segments in order; interval blocks are unrolled into "Intervall i/n" and "Pause".
    public static func blocks(from definition: WorkoutDefinition) -> [PlanBlock] {
        var result: [PlanBlock] = []
        var t = 0
        func add(_ title: String, _ duration: Int, _ fraction: Double?) {
            guard duration > 0 else { return }
            result.append(PlanBlock(title: title, start: t, duration: duration, fraction: fraction))
            t += duration
        }
        for s in definition.segments {
            switch s.kind {
            case .warmup: add("Aufwärmen", s.duration, mean(s.powerLow ?? 0.45, s.powerHigh ?? 0.75))
            case .steady:
                let text = s.text?.trimmingCharacters(in: .whitespaces) ?? ""
                add(text.isEmpty ? "Konstant" : text, s.duration, s.power ?? 0.6)
            case .ramp: add("Steigerung", s.duration, mean(s.powerLow ?? 0.45, s.powerHigh ?? 0.75))
            case .cooldown: add("Ausfahren", s.duration, mean(s.powerLow ?? 0.4, s.powerHigh ?? 0.65))
            case .freeRide: add("Frei fahren", s.duration, nil)
            case .intervals:
                let n = max(0, s.repeatCount ?? 1)
                if n > 0 {
                    for i in 1...n {
                        add("Intervall \(i)/\(n)", s.onDuration ?? 60, s.onPower ?? 1.0)
                        add("Pause", s.offDuration ?? 60, s.offPower ?? 0.5)
                    }
                }
            }
        }
        return result
    }

    private static func mean(_ a: Double, _ b: Double) -> Double { (a + b) / 2 }

    public struct Current: Equatable, Sendable {
        public var block: PlanBlock
        public var remaining: Int
        public var index: Int
    }

    /// The block running `elapsed` seconds after the start; nil before/after the plan.
    public static func current(in blocks: [PlanBlock], elapsed: Int) -> Current? {
        guard elapsed >= 0, let i = blocks.firstIndex(where: { elapsed >= $0.start && elapsed < $0.end }) else { return nil }
        return Current(block: blocks[i], remaining: blocks[i].end - elapsed, index: i)
    }
}

// MARK: - Interim file

/// The in-progress recording as JSON in Application Support (`recording-inprogress.json`).
public struct RecordingStore: Sendable {
    public let directory: URL
    public static let fileName = "recording-inprogress.json"

    public init(directory: URL = Self.defaultDirectory) { self.directory = directory }

    public static var defaultDirectory: URL {
        (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
    }

    var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    public func save(_ recording: StoredRecording) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(recording).write(to: fileURL, options: .atomic)
        } catch {
            Log.error(.strap, "Zwischenspeicherung der Aufzeichnung fehlgeschlagen: \(type(of: error))")
        }
    }

    public func load() -> StoredRecording? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(StoredRecording.self, from: data)
    }

    public func clear() { try? FileManager.default.removeItem(at: fileURL) }
}

// MARK: - Service

@MainActor
@Observable
public final class RecordingService {
    public static let shared = RecordingService(strap: StrapSession.shared)

    public static let saveInterval: TimeInterval = 30
    public static let presentInterval: TimeInterval = 5
    /// A pulse value older than this is shown as "no signal".
    static let staleAfter: TimeInterval = 10
    static let plausible = 30...250

    public private(set) var isRunning = false
    public private(set) var kind: RecordingKind = .ride
    public private(set) var title = ""
    public private(set) var startedAt: Date?
    public private(set) var plannedWorkoutID: UUID?
    public private(set) var plan: [PlanBlock] = []
    public private(set) var heartRate: Int?
    public private(set) var connected = false
    public private(set) var reconnects = 0
    /// Seconds since the start, refreshed by `tick()`.
    public private(set) var elapsed = 0
    /// A recording the app left behind (found at launch): resume or save it.
    public private(set) var interrupted: StoredRecording?
    public private(set) var lastResult: RecordingResult?

    private let strap: StrapSession?
    private let now: @Sendable () -> Date
    private let store: RecordingStore
    private let presenter: @MainActor () -> RecordingLivePresenting
    private let autoTick: Bool
    private var track: [UInt8] = []
    private var definition: WorkoutDefinition?
    /// Häkchen und Vorlage der laufenden Krafteinheit; gehen mit in die Zwischenspeicherung.
    public private(set) var strength: StoredStrengthState?
    private var lastSample: Date?
    private var lastSaved = Date.distantPast
    private var lastPresented = Date.distantPast
    private var lastPresentedBlock: String?
    private var lastState: StrapConnectionState = .idle
    private var ticker: Task<Void, Never>?
    private var strapToken: UUID?
    private var runID = UUID()

    public init(strap: StrapSession? = nil, now: @escaping @Sendable () -> Date = { .now },
                store: RecordingStore = RecordingStore(),
                presenter: @escaping @MainActor () -> RecordingLivePresenting = { RecordingLive.presenter },
                autoTick: Bool = true) {
        self.strap = strap
        self.now = now
        self.store = store
        self.presenter = presenter
        self.autoTick = autoTick
        interrupted = store.load()
        strapToken = strap?.addObserver { [weak self] event in self?.handle(event) }
    }

    // MARK: Derived

    /// Strap battery below 20 % (hint before the start).
    public var lowBattery: Bool { strap?.batteryLow == true && strap?.batteryLevel != nil }
    public var batteryLevel: Int? { strap?.batteryLevel }
    public var currentBlock: PlanBlock? { RecordingPlan.current(in: plan, elapsed: elapsed)?.block }

    // MARK: Start / stop

    public func start(kind: RecordingKind, title: String, plannedWorkoutID: UUID? = nil,
                      definition: WorkoutDefinition? = nil, startedAt: Date? = nil) {
        guard !isRunning else { return }
        begin(kind: kind, title: title, plannedWorkoutID: plannedWorkoutID, definition: definition,
              startedAt: startedAt ?? now(), track: [], reconnects: 0, id: UUID())
    }

    private func begin(kind: RecordingKind, title: String, plannedWorkoutID: UUID?, definition: WorkoutDefinition?,
                       startedAt: Date, track: [UInt8], reconnects: Int, id: UUID, strength: StoredStrengthState? = nil) {
        self.strength = strength
        runID = id
        self.kind = kind
        self.title = title
        self.plannedWorkoutID = plannedWorkoutID
        self.definition = definition
        self.plan = definition.map(RecordingPlan.blocks(from:)) ?? []
        self.startedAt = startedAt
        self.track = track
        self.reconnects = reconnects
        self.lastResult = nil
        heartRate = nil
        lastSample = nil
        lastState = strap?.state ?? .idle
        connected = strap?.isConnected ?? false
        elapsed = max(0, Int(now().timeIntervalSince(startedAt)))
        lastSaved = now()
        isRunning = true
        if let strap, strap.state == .idle { strap.reconnectSaved() }
        presenter().start(liveState())
        lastPresented = now()
        lastPresentedBlock = currentBlock?.title
        startTicker()
    }

    /// Ends the recording and returns its result; nil when none is running.
    @discardableResult
    public func stop() -> RecordingResult? {
        guard isRunning, let startedAt else { return nil }
        let end = now()
        let result = makeResult(startedAt: startedAt, end: end)
        isRunning = false
        ticker?.cancel()
        ticker = nil
        store.clear()
        presenter().end(liveState())
        lastResult = result
        return result
    }

    // MARK: Input

    /// A pulse value at `date`: the last value of a second wins; implausible values count as no value.
    public func ingest(heartRate bpm: Int, at date: Date) {
        guard isRunning, let startedAt, Self.plausible.contains(bpm) else { return }
        let index = Int(date.timeIntervalSince(startedAt).rounded(.down))
        guard index >= 0, index < FITParser.maxSeriesSeconds else { return }
        if track.count <= index { track.append(contentsOf: [UInt8](repeating: 0, count: index + 1 - track.count)) }
        track[index] = UInt8(bpm)
        heartRate = bpm
        lastSample = date
    }

    /// Connection changes; every drop into `reconnecting` counts once.
    public func ingest(state: StrapConnectionState) {
        guard isRunning else { return }
        if state == .reconnecting, lastState != .reconnecting { reconnects += 1 }
        lastState = state
        connected = state == .connected
        if state != .connected, state != .reconnecting, state != .connecting { heartRate = nil }
    }

    private func handle(_ event: StrapEvent) {
        switch event {
        case .measurement(let m, let date): ingest(heartRate: m.heartRate, at: date)
        case .state(let s): ingest(state: s)
        default: break
        }
    }

    /// Merkt sich Häkchen und Vorlage der Krafteinheit und sichert sie sofort mit der Pulsspur (ein Häkchen darf bei einem
    /// App-Abbruch nicht verloren gehen). Ohne laufende Aufzeichnung passiert nichts.
    public func updateStrength(_ state: StoredStrengthState?) {
        guard isRunning, let startedAt, strength != state else { return }
        strength = state
        store.save(snapshot(startedAt: startedAt, end: now()))
        lastSaved = now()
    }

    // MARK: Timer work

    /// Once per second: elapsed time, interim save (30 s), lock-screen update (5 s or block change).
    public func tick() {
        guard isRunning, let startedAt else { return }
        let current = now()
        elapsed = max(0, Int(current.timeIntervalSince(startedAt)))
        if let lastSample, current.timeIntervalSince(lastSample) > Self.staleAfter { heartRate = nil }
        if current.timeIntervalSince(lastSaved) >= Self.saveInterval {
            store.save(snapshot(startedAt: startedAt, end: current))
            lastSaved = current
        }
        let block = currentBlock?.title
        if current.timeIntervalSince(lastPresented) >= Self.presentInterval || block != lastPresentedBlock {
            presenter().update(liveState())
            lastPresented = current
            lastPresentedBlock = block
        }
    }

    private func startTicker() {
        ticker?.cancel()
        guard autoTick else { return }
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.isRunning else { return }
                self.tick()
            }
        }
    }

    // MARK: Interrupted recording

    /// Continues the recording the app left behind; the time in between stays a gap.
    public func resumeInterrupted() {
        guard !isRunning, let saved = interrupted else { return }
        interrupted = nil
        begin(kind: saved.kind, title: saved.title, plannedWorkoutID: saved.plannedWorkoutID, definition: saved.definition,
              startedAt: saved.startedAt, track: saved.heartRateSeconds, reconnects: saved.reconnects, id: saved.id, strength: saved.strength)
    }

    /// Ends the left-behind recording at the time of its last interim save.
    public func finishInterrupted() -> RecordingResult? {
        guard let saved = interrupted else { return nil }
        interrupted = nil
        store.clear()
        guard !saved.heartRate.isEmpty else { return nil }
        let result = saved.result
        lastResult = result
        return result
    }

    public func discardInterrupted() {
        interrupted = nil
        store.clear()
    }

    // MARK: Helpers

    private func padded(to count: Int) -> [UInt8] {
        track.count >= count ? Array(track.prefix(count)) : track + [UInt8](repeating: 0, count: count - track.count)
    }

    private func snapshot(startedAt: Date, end: Date) -> StoredRecording {
        let seconds = padded(to: max(0, Int(end.timeIntervalSince(startedAt))))
        return StoredRecording(id: runID, kind: kind, title: title, startedAt: startedAt, endedAt: end,
                               heartRate: Data(seconds), gapSeconds: seconds.filter { $0 == 0 }.count, reconnects: reconnects,
                               plannedWorkoutID: plannedWorkoutID, definition: definition, strength: strength)
    }


    private func makeResult(startedAt: Date, end: Date) -> RecordingResult {
        let hr = padded(to: max(1, Int(end.timeIntervalSince(startedAt))))
        return RecordingResult(id: runID, kind: kind, title: title, startedAt: startedAt, endedAt: end,
                               seconds: RideSeconds(power: [UInt16](repeating: 0, count: hr.count), heartRate: hr),
                               gapSeconds: hr.filter { $0 == 0 }.count, reconnects: reconnects,
                               plannedWorkoutID: plannedWorkoutID)
    }

    private func liveState() -> RecordingLiveState {
        let block = currentBlock
        return RecordingLiveState(kind: kind, title: title, startedAt: startedAt ?? now(), heartRate: heartRate,
                                  connected: connected, blockTitle: block?.title,
                                  blockEndsAt: block.flatMap { b in startedAt.map { $0.addingTimeInterval(TimeInterval(b.end)) } })
    }
}
