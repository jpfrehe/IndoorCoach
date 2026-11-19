@preconcurrency import CoreBluetooth
import Foundation

// BLE chest-strap access (backlog B35). Scans only for the Heart Rate service (0x180D), only on request while the
// app is in the foreground, and keeps the connection alive afterwards (bluetooth-central background mode).
// Nothing leaves the device.

// MARK: - Types

public enum StrapUnavailableReason: Equatable, Sendable {
    case bluetoothOff, unauthorized, unsupported
}

public enum StrapConnectionState: Equatable, Sendable {
    case idle
    case scanning
    case connecting
    case connected
    /// Connection dropped; a new connect is already pending (it completes as soon as the strap is back).
    case reconnecting
    case unavailable(StrapUnavailableReason)
}

public struct DiscoveredStrap: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    /// Signal strength in dBm (about -40 very close ... -90 weak).
    public var rssi: Int

    public init(id: UUID, name: String, rssi: Int) {
        self.id = id
        self.name = name
        self.rssi = rssi
    }
}

public enum StrapEvent: Sendable {
    case state(StrapConnectionState)
    case discovered(DiscoveredStrap)
    case measurement(HeartRateMeasurement, at: Date)
    case battery(Int)
    case deviceInfo(name: String?, manufacturer: String?, model: String?)
}

/// Strap access behind a protocol so the UI and tests run against a stub. `events` can have one consumer.
public protocol HeartRateStrapControlling: AnyObject, Sendable {
    var events: AsyncStream<StrapEvent> { get }
    /// Peripheral stored from the last successful connection.
    var savedStrapID: UUID? { get }
    func startScan()
    func stopScan()
    /// Connects and keeps reconnecting after drops until `disconnect()` or `forget()`.
    func connect(_ id: UUID)
    func disconnect()
    /// Disconnects and removes the stored peripheral ID.
    func forget()
}

/// Remembers the strap's peripheral identifier (a random per-phone UUID, no personal data).
public struct StrapStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "heartRateStrap.peripheralID"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var savedID: UUID? {
        get { defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) }
        nonmutating set {
            if let newValue { defaults.set(newValue.uuidString, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }
}

// MARK: - CoreBluetooth

/// Concurrency: every CoreBluetooth object is created and touched on `queue` only (the manager's delegate queue),
/// public methods hop onto it, results leave through the `Sendable` AsyncStream continuation. Hence `@unchecked
/// Sendable`: the mutable state is confined to the serial queue.
public final class CoreBluetoothStrapController: NSObject, HeartRateStrapControlling, @unchecked Sendable {
    private nonisolated(unsafe) static let heartRate = CBUUID(string: "180D")
    private nonisolated(unsafe) static let measurement = CBUUID(string: "2A37")
    private nonisolated(unsafe) static let batteryService = CBUUID(string: "180F")
    private nonisolated(unsafe) static let batteryLevel = CBUUID(string: "2A19")
    private nonisolated(unsafe) static let deviceInfo = CBUUID(string: "180A")
    private nonisolated(unsafe) static let manufacturer = CBUUID(string: "2A29")
    private nonisolated(unsafe) static let modelNumber = CBUUID(string: "2A24")

    public let events: AsyncStream<StrapEvent>
    private let continuation: AsyncStream<StrapEvent>.Continuation
    private let queue = DispatchQueue(label: "app.indoorcoach.strap")
    private let store: StrapStore

    // Confined to `queue`:
    private var central: CBCentralManager?
    private var known: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var wantsConnection = false
    private var wantsScan = false
    private var pendingConnectID: UUID?
    private var manufacturerName: String?
    private var modelName: String?

    public init(store: StrapStore = StrapStore()) {
        self.store = store
        (events, continuation) = AsyncStream.makeStream(of: StrapEvent.self, bufferingPolicy: .bufferingNewest(256))
        super.init()
    }

    public var savedStrapID: UUID? { store.savedID }

    public func startScan() {
        queue.async { [self] in
            wantsScan = true
            ensureCentral()
            beginScanIfPossible()
        }
    }

    public func stopScan() {
        queue.async { [self] in
            wantsScan = false
            central?.stopScan()
            if !wantsConnection { continuation.yield(.state(.idle)) }
        }
    }

    public func connect(_ id: UUID) {
        queue.async { [self] in
            wantsConnection = true
            pendingConnectID = id
            ensureCentral()
            connectPendingIfPossible()
        }
    }

    public func disconnect() {
        queue.async { [self] in
            wantsConnection = false
            pendingConnectID = nil
            if let peripheral { central?.cancelPeripheralConnection(peripheral) }
            peripheral = nil
            continuation.yield(.state(.idle))
        }
    }

    public func forget() {
        store.savedID = nil
        disconnect()
    }

    // MARK: Queue-confined helpers

    private func ensureCentral() {
        guard central == nil else { return }
        // Created lazily: this is what triggers the Bluetooth permission prompt, after our own explanation.
        central = CBCentralManager(delegate: self, queue: queue)
    }

    private func beginScanIfPossible() {
        guard wantsScan, let central, central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: [Self.heartRate], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        continuation.yield(.state(.scanning))
    }

    private func connectPendingIfPossible() {
        guard wantsConnection, let central, central.state == .poweredOn, let id = pendingConnectID else { return }
        let target = known[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first
        guard let target else {
            // Not known to this phone any more (e.g. after "forget" on the iPhone side): fall back to scanning.
            wantsScan = true
            beginScanIfPossible()
            return
        }
        peripheral = target
        target.delegate = self
        continuation.yield(.state(.connecting))
        central.connect(target)   // a pending connect never times out; it completes when the strap is in range
    }

    private func reconnect() {
        guard wantsConnection, let central, let peripheral else { return }
        continuation.yield(.state(.reconnecting))
        central.connect(peripheral)
    }
}

extension CoreBluetoothStrapController: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            beginScanIfPossible()
            connectPendingIfPossible()
        case .poweredOff: continuation.yield(.state(.unavailable(.bluetoothOff)))
        case .unauthorized: continuation.yield(.state(.unavailable(.unauthorized)))
        case .unsupported: continuation.yield(.state(.unavailable(.unsupported)))
        default: break   // .unknown / .resetting: wait for the next callback
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        known[peripheral.identifier] = peripheral
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Pulsgurt"
        continuation.yield(.discovered(DiscoveredStrap(id: peripheral.identifier, name: name, rssi: RSSI.intValue)))
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        store.savedID = peripheral.identifier
        wantsScan = false
        central.stopScan()
        continuation.yield(.state(.connected))
        peripheral.discoverServices([Self.heartRate, Self.batteryService, Self.deviceInfo])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        reconnect()
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // Immediately ask again; iOS completes it when the strap is reachable (also with the display locked).
        reconnect()
    }
}

extension CoreBluetoothStrapController: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            switch service.uuid {
            case Self.heartRate: peripheral.discoverCharacteristics([Self.measurement], for: service)
            case Self.batteryService: peripheral.discoverCharacteristics([Self.batteryLevel], for: service)
            case Self.deviceInfo: peripheral.discoverCharacteristics([Self.manufacturer, Self.modelNumber], for: service)
            default: break
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case Self.measurement: peripheral.setNotifyValue(true, for: characteristic)
            case Self.batteryLevel:
                peripheral.readValue(for: characteristic)
                peripheral.setNotifyValue(true, for: characteristic)
            case Self.manufacturer, Self.modelNumber: peripheral.readValue(for: characteristic)
            default: break
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        switch characteristic.uuid {
        case Self.measurement:
            if let m = HeartRateMeasurement.parse(data) { continuation.yield(.measurement(m, at: .now)) }
        case Self.batteryLevel:
            if let level = BatteryLevel.parse(data) { continuation.yield(.battery(level)) }
        case Self.manufacturer:
            manufacturerName = String(data: data, encoding: .utf8)
            yieldDeviceInfo(peripheral)
        case Self.modelNumber:
            modelName = String(data: data, encoding: .utf8)
            yieldDeviceInfo(peripheral)
        default: break
        }
    }

    private func yieldDeviceInfo(_ peripheral: CBPeripheral) {
        continuation.yield(.deviceInfo(name: peripheral.name, manufacturer: manufacturerName, model: modelName))
    }
}

// MARK: - Stub

/// Stand-in for tests, demo and UI tests (`-uiStrapStub YES`). With `autoplay` it finds one strap shortly after
/// `startScan()` and, once connected, sends a pulse about once a second; otherwise tests drive it with `emit`.
public final class StubStrapController: HeartRateStrapControlling, @unchecked Sendable {
    public let events: AsyncStream<StrapEvent>
    private let continuation: AsyncStream<StrapEvent>.Continuation
    private let autoplay: Bool
    private let lock = NSLock()
    private var scanning = false
    private var didForget = false
    private var saved: UUID?
    private var playback: Task<Void, Never>?
    private let stubID = UUID()

    public init(autoplay: Bool) {
        self.autoplay = autoplay
        (events, continuation) = AsyncStream.makeStream(of: StrapEvent.self, bufferingPolicy: .bufferingNewest(256))
    }

    public var savedStrapID: UUID? { lock.withLock { saved } }
    public var isScanning: Bool { lock.withLock { scanning } }
    public var forgotten: Bool { lock.withLock { didForget } }

    public func emit(_ event: StrapEvent) { continuation.yield(event) }

    public func startScan() {
        lock.withLock { scanning = true }
        continuation.yield(.state(.scanning))
        guard autoplay else { return }
        let strap = DiscoveredStrap(id: stubID, name: "TICKR Stub 4711", rssi: -52)
        Task { [continuation] in
            try? await Task.sleep(for: .milliseconds(200))
            continuation.yield(.discovered(strap))
        }
    }

    public func stopScan() {
        lock.withLock { scanning = false }
    }

    public func connect(_ id: UUID) {
        lock.withLock { saved = id; scanning = false }
        continuation.yield(.state(.connecting))
        guard autoplay else { return }
        let task = Task { [continuation] in
            try? await Task.sleep(for: .milliseconds(200))
            continuation.yield(.state(.connected))
            continuation.yield(.battery(87))
            continuation.yield(.deviceInfo(name: "TICKR Stub 4711", manufacturer: "Wahoo", model: nil))
            var beat = 0
            while !Task.isCancelled {
                // Flags 0x10: 8-bit pulse plus one RR value; rr is 1/1024 s.
                let pulse = 118 + (beat % 7)
                let rrRaw = UInt16(1024 * 60 / pulse)
                let data = Data([0x10, UInt8(pulse), UInt8(rrRaw & 0xFF), UInt8(rrRaw >> 8)])
                if let m = HeartRateMeasurement.parse(data) { continuation.yield(.measurement(m, at: .now)) }
                beat += 1
                try? await Task.sleep(for: .seconds(1))
            }
        }
        lock.withLock { playback?.cancel(); playback = task }
    }

    public func disconnect() {
        lock.withLock { playback?.cancel() }
        continuation.yield(.state(.idle))
    }

    public func forget() {
        lock.withLock { saved = nil; didForget = true }
        disconnect()
    }
}
