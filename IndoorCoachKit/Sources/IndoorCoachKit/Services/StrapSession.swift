import Foundation
import Observation

/// Main-actor view model on top of `HeartRateStrapControlling`: turns the event stream into observable state and
/// runs the device-test protocol (B26). Holds no history of pulse values.
@MainActor
@Observable
public final class StrapSession {
    /// Shared so the connection survives leaving the devices screen. The CoreBluetooth manager is only created on
    /// the first scan/connect, i.e. after the user has seen the explanation.
    public static let shared: StrapSession = {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "uiStrapStub") {
            return StrapSession(controller: StubStrapController(autoplay: true))
        }
        #endif
        return StrapSession(controller: CoreBluetoothStrapController())
    }()

    public private(set) var state: StrapConnectionState = .idle
    public private(set) var discovered: [DiscoveredStrap] = []
    public private(set) var liveHeartRate: Int?
    public private(set) var contact: HeartRateMeasurement.SensorContact = .unsupported
    public private(set) var rrSeen = false
    public private(set) var batteryLevel: Int?
    public private(set) var deviceName: String?
    public private(set) var manufacturer: String?
    public private(set) var protocolRunning = false
    public private(set) var protocolPackets = 0
    public private(set) var protocolGaps = 0
    public private(set) var protocolReconnects = 0
    public private(set) var lastProtocolReport: [String] = []

    private let controller: any HeartRateStrapControlling
    private let now: @Sendable () -> Date
    private var recorder: StrapProtocolRecorder?
    private var appActive = true
    private var eventTask: Task<Void, Never>?   // ends with the stream; holds self weakly
    // ANCHOR-REC: the event stream has one consumer (this session); the recording taps it here.
    private var observers: [UUID: @MainActor (StrapEvent) -> Void] = [:]

    public init(controller: any HeartRateStrapControlling, now: @escaping @Sendable () -> Date = { .now }) {
        self.controller = controller
        self.now = now
        let events = controller.events
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                self.handle(event)
            }
        }
    }


    // MARK: Observers (ANCHOR-REC)

    /// Calls `handler` for every strap event (after the session's own state is updated). Returns a token for `removeObserver`.
    @discardableResult
    public func addObserver(_ handler: @escaping @MainActor (StrapEvent) -> Void) -> UUID {
        let token = UUID()
        observers[token] = handler
        return token
    }

    public func removeObserver(_ token: UUID) { observers[token] = nil }

    // MARK: Derived

    public var savedStrapID: UUID? { controller.savedStrapID }
    public var hint: StrapModelHint? { deviceName.map { StrapModelHints.hint(forName: $0) } }
    public var batteryLow: Bool { (batteryLevel ?? 100) < 20 }
    public var isConnected: Bool { state == .connected }

    // MARK: Actions

    public func startScan() {
        discovered = []
        controller.startScan()
    }

    public func stopScan() { controller.stopScan() }

    public func connect(_ id: UUID) {
        if let strap = discovered.first(where: { $0.id == id }) { deviceName = strap.name }
        controller.connect(id)
    }

    /// Reconnects to the remembered strap, if any (no scan needed).
    public func reconnectSaved() {
        if let id = controller.savedStrapID, state == .idle { controller.connect(id) }
    }

    public func disconnect() {
        controller.disconnect()
        liveHeartRate = nil
    }

    public func forget() {
        controller.forget()
        resetDevice()
        state = .idle
    }

    /// The device test must record whether the app was in front or not. Scanning stops when it leaves the front.
    public func setAppActive(_ active: Bool) {
        appActive = active
        recorder?.setAppActive(active, at: now())
        if !active, state == .scanning { controller.stopScan() }
    }

    // MARK: Device test (B26)

    public func startProtocol() {
        recorder = StrapProtocolRecorder(start: now(), battery: batteryLevel, appActive: appActive,
                                         modelName: StrapModelHints.hint(forName: deviceName).model)
        protocolRunning = true
        lastProtocolReport = []
        syncCounters()
    }

    /// Ends the protocol, writes the redacted lines into the diagnostics log and returns them.
    @discardableResult
    public func stopProtocol() -> [String] {
        guard let recorder else { return lastProtocolReport }
        let lines = recorder.reportLines(end: now())
        for line in lines { Log.notice(.strap, line) }
        lastProtocolReport = lines
        self.recorder = nil
        protocolRunning = false
        return lines
    }

    // MARK: Events

    private func handle(_ event: StrapEvent) {
        switch event {
        case .state(let new):
            if new == .reconnecting { recorder?.reconnect() }
            if new != .connected, new != .reconnecting, new != .connecting { liveHeartRate = nil }
            state = new
            Log.notice(.strap, "Verbindung: \(String(describing: new))")
        case .discovered(let strap):
            if let i = discovered.firstIndex(where: { $0.id == strap.id }) { discovered[i] = strap } else { discovered.append(strap) }
            discovered.sort { $0.rssi > $1.rssi }
        case .measurement(let m, let date):
            liveHeartRate = m.heartRate
            contact = m.contact
            if !m.rrIntervalsMs.isEmpty { rrSeen = true }
            recorder?.packet(at: date, hasRR: !m.rrIntervalsMs.isEmpty)
        case .battery(let level):
            batteryLevel = level
            recorder?.setBattery(level)
        case .deviceInfo(let name, let manufacturer, _):
            if let name, !name.isEmpty { deviceName = name }
            if let manufacturer, !manufacturer.isEmpty { self.manufacturer = manufacturer }
        }
        syncCounters()
        for handler in observers.values { handler(event) }
    }

    private func syncCounters() {
        protocolPackets = recorder?.packetCount ?? protocolPackets
        protocolGaps = recorder?.gaps.count ?? protocolGaps
        protocolReconnects = recorder?.reconnects ?? protocolReconnects
    }

    private func resetDevice() {
        liveHeartRate = nil
        batteryLevel = nil
        deviceName = nil
        manufacturer = nil
        rrSeen = false
        contact = .unsupported
    }
}
