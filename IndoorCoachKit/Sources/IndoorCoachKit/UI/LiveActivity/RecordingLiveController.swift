import Foundation

/// Dünne Schicht über ActivityKit, damit die Zustandsmaschine ohne ActivityKit testbar bleibt.
@MainActor
public protocol RecordingActivityBackend: AnyObject {
    /// `false`, wenn der Nutzer Live Activities abgeschaltet hat oder die Plattform sie nicht kennt.
    var isAvailable: Bool { get }
    /// `true`, wenn die Aktivität läuft.
    func request(_ state: RecordingLiveState, staleDate: Date) -> Bool
    func update(_ state: RecordingLiveState, staleDate: Date) async
    func end(_ state: RecordingLiveState, dismissAfter: TimeInterval) async
    /// Beendet jede noch laufende Aktivität dieser App sofort (Reste eines Absturzes oder Neustarts).
    func endAll() async
}

extension RecordingActivityBackend {
    public func endAll() async {}
}

/// Setzt `RecordingLivePresenting` auf ein `RecordingActivityBackend` um: toleriert beliebige Aufrufreihenfolgen,
/// fehlende Berechtigung (Noop) und wirft nie in die Aufzeichnung. Aufrufe werden der Reihe nach abgearbeitet.
@MainActor
public final class RecordingLiveController: RecordingLivePresenting {
    private enum Phase { case idle, running, ended }

    /// Wie lange das Ende auf dem Sperrbildschirm stehen bleibt.
    public static let dismissDelay: TimeInterval = 60

    private let backend: RecordingActivityBackend
    private let now: @MainActor () -> Date
    private var phase = Phase.idle
    private var lastState: RecordingLiveState?
    private var tail: Task<Void, Never>?
    /// Nur innerhalb der Warteschlange geändert: das Backend hält eine laufende Aktivität.
    private var backendActive = false

    public init(backend: RecordingActivityBackend, now: @escaping @MainActor () -> Date = { Date() }) {
        self.backend = backend
        self.now = now
    }

    public var isRunning: Bool { phase == .running }

    public func start(_ state: RecordingLiveState) {
        if phase == .running { update(state); return }   // doppelter Start: nur aktualisieren
        phase = .idle
        begin(state)
    }

    public func update(_ state: RecordingLiveState) {
        switch phase {
        case .ended: return                 // späte Updates beleben die Aktivität nicht neu
        case .idle: begin(state)            // Update vor Start
        case .running:
            guard state != lastState else { return }
            lastState = state
            let stale = RecordingLiveDisplay.staleDate(from: now())
            enqueue { [self] in if backendActive { await backend.update(state, staleDate: stale) } }
        }
    }

    public func end(_ state: RecordingLiveState?) {
        let wasRunning = phase == .running
        phase = .ended
        guard wasRunning, let final = state ?? lastState else { return }
        lastState = nil
        enqueue { [self] in
            guard backendActive else { return }
            backendActive = false
            await backend.end(final, dismissAfter: Self.dismissDelay)
        }
    }

    /// Beim App-Start: Live Activities beenden, die ein Absturz oder Neustart zurückgelassen hat. Nur, wenn gerade keine
    /// Aufzeichnung läuft.
    public func endOrphans() async {
        guard phase != .running else { return }
        await tail?.value
        guard phase != .running else { return }
        await backend.endAll()
    }

    /// Wartet, bis alle bisherigen Aufrufe beim Backend angekommen sind (für Tests).
    public func waitUntilIdle() async { await tail?.value }

    private func begin(_ state: RecordingLiveState) {
        guard backend.isAvailable else { return }
        phase = .running
        lastState = state
        let stale = RecordingLiveDisplay.staleDate(from: now())
        // Der Request läuft in derselben Warteschlange wie Update/Ende, damit ein Neustart nicht vor dem Ende des
        // alten Laufs ankommt.
        enqueue { [self] in backendActive = backend.request(state, staleDate: stale) }
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            await work()
        }
    }
}
