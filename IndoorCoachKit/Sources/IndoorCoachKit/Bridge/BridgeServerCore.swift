import Foundation
import Network

/// Implementation behind `BridgeServer`. Mutable state is guarded by `lock`; network callbacks run on `queue`.
final class BridgeServerCore: @unchecked Sendable {
    private let name: String
    private let source: any BridgeRideSource
    private let advertise: Bool
    private let queue = DispatchQueue(label: "app.indoorcoach.bridge.server")
    private let lock = NSLock()

    private var secret: Data
    private var mainListener: NWListener?
    private var pairingListener: NWListener?
    private var mainPort: UInt16?
    private var pairingPortValue: UInt16?
    private var connections: [ObjectIdentifier: BridgeChannel] = [:]
    private var pairingTimer: DispatchWorkItem?
    private var pairingCode: String?
    private var eventHandler: (@Sendable (BridgeServer.Event) -> Void)?
    /// Pairing hardening (security review): failed handshakes close the window, few connections at a time,
    /// one pairing per window.
    static let maxPairingFailures = 10
    static let maxPairingConnections = 4
    private var pairingFailures = 0
    private var pairingInFlight = 0
    private var pairedThisWindow = false
    /// Abnormal connection ends (for tests); a clean close by the phone is not recorded.
    private var endErrors: [String] = []
    var connectionEndErrors: [String] { lock.withLock { endErrors } }

    init(name: String, secret: Data, source: any BridgeRideSource, advertise: Bool) {
        self.name = name
        self.secret = secret
        self.source = source
        self.advertise = advertise
    }

    var onEvent: (@Sendable (BridgeServer.Event) -> Void)? {
        get { lock.withLock { eventHandler } }
        set { lock.withLock { eventHandler = newValue } }
    }

    var port: UInt16? { lock.withLock { mainPort } }
    var pairingPort: UInt16? { lock.withLock { pairingPortValue } }

    private func emit(_ deviceName: String, _ kind: BridgeServer.Event.Kind) {
        let handler = onEvent
        queue.async { handler?(BridgeServer.Event(deviceName: deviceName, kind: kind)) }
    }

    // MARK: Listeners

    func start() async throws {
        let key = lock.withLock { secret }
        let listener = try await makeListener(psk: key, identity: BridgeCrypto.mainIdentity,
                                              serviceType: Bridge.serviceType, pairing: false)
        let old: NWListener? = lock.withLock {
            let previous = mainListener
            mainListener = listener
            mainPort = listener.port?.rawValue
            return previous
        }
        old?.cancel()
        Log.notice(.bridge, "server started")
    }

    func stop() {
        let (main, pair, conns, timer) = lock.withLock { () -> (NWListener?, NWListener?, [BridgeChannel], DispatchWorkItem?) in
            let result = (mainListener, pairingListener, Array(connections.values), pairingTimer)
            mainListener = nil; pairingListener = nil; mainPort = nil; pairingPortValue = nil
            connections = [:]; pairingTimer = nil; pairingCode = nil
            return result
        }
        timer?.cancel()
        main?.cancel(); pair?.cancel()
        conns.forEach { $0.cancel() }
    }

    func startPairing(code: String) async throws {
        stopPairing()
        let listener = try await makeListener(psk: BridgeCrypto.pairingKey(code: code),
                                              identity: BridgeCrypto.pairingIdentity,
                                              serviceType: Bridge.pairingServiceType, pairing: true)
        let timer = DispatchWorkItem { [weak self] in self?.stopPairing() }
        lock.withLock {
            pairingListener = listener
            pairingPortValue = listener.port?.rawValue
            pairingTimer = timer
            pairingCode = code
            pairingFailures = 0
            pairedThisWindow = false
        }
        let seconds = Bridge.pairingWindow.components.seconds
        queue.asyncAfter(deadline: .now() + .seconds(Int(seconds)), execute: timer)
        Log.notice(.bridge, "pairing window opened")
    }

    func stopPairing() {
        let (listener, timer) = lock.withLock { () -> (NWListener?, DispatchWorkItem?) in
            let result = (pairingListener, pairingTimer)
            pairingListener = nil; pairingPortValue = nil; pairingTimer = nil; pairingCode = nil
            return result
        }
        timer?.cancel()
        if let listener {
            listener.cancel()
            Log.notice(.bridge, "pairing window closed")
        }
    }

    /// Replaces the secret: the old listener (old PSK) is closed first so no phone with the old secret gets in, then
    /// the main listener restarts with the new one (the port changes). Retries a few times if the restart fails.
    func updateSecret(_ newSecret: Data) {
        let (old, conns) = lock.withLock { () -> (NWListener?, [BridgeChannel]) in
            secret = newSecret
            let result = (mainListener, Array(connections.values))
            mainListener = nil
            mainPort = nil
            connections = [:]
            return result
        }
        guard let old else { return }
        old.cancel()
        conns.forEach { $0.cancel() }
        Task { [self] in
            for attempt in 1...5 {
                do {
                    try await start()
                    return
                } catch {
                    Log.error(.bridge, "restart after new secret failed (\(attempt)/5): \(type(of: error))")
                    try? await Task.sleep(for: .seconds(attempt))
                }
            }
        }
    }

    private func makeListener(psk: Data, identity: String, serviceType: String, pairing: Bool) async throws -> NWListener {
        let listener = try NWListener(using: BridgeCrypto.parameters(psk: psk, identity: identity))
        if advertise { listener.service = NWListener.Service(name: name, type: serviceType) }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection, pairing: pairing)
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let once = ResumeGuard()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: once.run { cont.resume() }
                case .failed(let error):
                    once.run { cont.resume(throwing: error) }
                    listener.cancel()
                case .cancelled: once.run { cont.resume(throwing: BridgeError.unreachable) }
                default: break
                }
            }
            listener.start(queue: queue)
        }
        return listener
    }

    // MARK: Connections

    private func accept(_ connection: NWConnection, pairing: Bool) {
        if pairing {
            let admitted = lock.withLock { () -> Bool in
                guard pairingInFlight < Self.maxPairingConnections, !pairedThisWindow else { return false }
                pairingInFlight += 1
                return true
            }
            guard admitted else { connection.cancel(); return }
        }
        let channel = BridgeChannel(connection: connection, queue: queue)
        let key = ObjectIdentifier(channel)
        lock.withLock { connections[key] = channel }
        Task { [self] in
            defer {
                channel.cancel()
                lock.withLock {
                    connections.removeValue(forKey: key)
                    if pairing { pairingInFlight -= 1 }
                }
            }
            do {
                try await channel.start(timeout: pairing ? 8 : 15)
            } catch {
                if pairing { countPairingFailure() }
                Log.notice(.bridge, "connection ended: \(error)")
                return
            }
            do {
                if pairing { try await servePairing(channel) } else { try await serveMain(channel) }
            } catch is BridgeChannelClosed {
                // the phone is done
            } catch {
                lock.withLock { endErrors.append("\(error)") }
                Log.notice(.bridge, "connection ended: \(error)")
            }
        }
    }

    /// A failed TLS handshake on the pairing service is a wrong code (or a scan): after a few, the window closes.
    private func countPairingFailure() {
        let exhausted = lock.withLock { () -> Bool in
            pairingFailures += 1
            return pairingFailures >= Self.maxPairingFailures && pairingListener != nil
        }
        if exhausted {
            Log.notice(.bridge, "pairing window closed after \(Self.maxPairingFailures) failed attempts")
            stopPairing()
        }
    }

    private func servePairing(_ channel: BridgeChannel) async throws {
        guard case .hello(let device, _) = try await channel.receive(timeout: 10) else {
            try? await channel.send(.failure("hello expected"))
            return
        }
        guard case .pairingRequest(let publicKey) = try await channel.receive(timeout: 10) else {
            try? await channel.send(.failure("pairing request expected"))
            return
        }
        // Exactly one pairing per window, even if two phones completed the handshake at the same time.
        let claim = lock.withLock { () -> (secret: Data, code: String)? in
            guard !pairedThisWindow, let code = pairingCode else { return nil }
            pairedThisWindow = true
            return (secret, code)
        }
        guard let claim else {
            try? await channel.send(.failure("pairing window closed"))
            return
        }
        let sealed = try BridgePairingSeal.seal(secret: claim.secret, clientPublicKey: publicKey, code: claim.code)
        try await channel.send(.pairingSecret(sealed, macName: name))
        emit(device, .paired)
        Log.notice(.bridge, "paired a device")
        stopPairing()
        // Give the client time to read the answer before the connection is closed.
        _ = try? await channel.receive(timeout: 3)
    }

    private func serveMain(_ channel: BridgeChannel) async throws {
        guard case .hello(let device, let version) = try await channel.receive(timeout: 10) else {
            try? await channel.send(.failure("hello expected"))
            return
        }
        guard version == Bridge.protocolVersion else {
            try? await channel.send(.failure("protocol version \(Bridge.protocolVersion) required"))
            return
        }
        try await channel.send(.welcome(macName: name, protocolVersion: Bridge.protocolVersion))
        emit(device, .connected)
        while true {
            let request = try await channel.receive(timeout: 60)
            switch request {
            case .listRides(let since):
                let rides = await source.rides(since: since)
                try await channel.send(.rides(rides))
                emit(device, .listed(rides.count))
                Log.notice(.bridge, "listed \(rides.count) rides")
            case .fetchRide(let id):
                if let fit = await source.fitData(id: id) {
                    try await channel.send(.rideData(id: id, fit: fit))
                    emit(device, .fetched(id))
                    Log.notice(.bridge, "served a ride (\(fit.count) bytes)")
                } else {
                    try await channel.send(.failure("unknown ride"))
                }
            default:
                try await channel.send(.failure("unexpected message"))
            }
        }
    }
}

final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func run(_ body: () -> Void) {
        let first = lock.withLock { () -> Bool in
            defer { done = true }
            return !done
        }
        if first { body() }
    }
}
