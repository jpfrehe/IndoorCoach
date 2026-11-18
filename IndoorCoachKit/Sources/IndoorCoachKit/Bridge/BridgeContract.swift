import CryptoKit
import Foundation
import Network
import Security

// Contract for the "IndoorCoach Brücke" (docs/14-SEKUNDENDATEN-MAC-BRUECKE.md).
// The Mac menu-bar app reads MyWhoosh's FIT files and serves them on the local network; the iOS app fetches them.
// S0 stubs: public signatures are fixed. B1 implements the bodies (and may add internal helpers in other files),
// B2 (iOS) and B3 (macOS) build against these signatures.

public enum Bridge {
    /// Bonjour service of a paired bridge (TLS with the long pairing secret).
    public static let serviceType = "_indoorcoach._tcp"
    /// Bonjour service that only exists while the Mac shows a pairing code (TLS with a key derived from the code).
    public static let pairingServiceType = "_icpair._tcp"
    public static let protocolVersion = 1
    /// Upper bound for one message (a 3-hour FIT file is ~1–2 MB).
    public static let maxMessageBytes = 20 * 1024 * 1024
    /// How long a pairing code stays valid.
    public static let pairingWindow: Duration = .seconds(300)
}

/// One ride the bridge offers. `id` is stable across scans and devices: `fit-<unix start seconds>`.
public struct BridgeRide: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var startDate: Date
    public var durationSeconds: Int
    public var byteCount: Int
    /// When the bridge picked the file up – used for `listRides(since:)`.
    public var addedAt: Date

    public init(id: String, startDate: Date, durationSeconds: Int, byteCount: Int, addedAt: Date) {
        self.id = id
        self.startDate = startDate
        self.durationSeconds = durationSeconds
        self.byteCount = byteCount
        self.addedAt = addedAt
    }

    public static func id(forStart start: Date) -> String { "fit-\(Int(start.timeIntervalSince1970))" }
}

public enum BridgeMessage: Sendable, Equatable {
    /// client → server, first message on every connection.
    case hello(deviceName: String, protocolVersion: Int)
    /// server → client answer to `hello` on the main service.
    case welcome(macName: String, protocolVersion: Int)
    /// server → client answer to `hello` on the pairing service: the long secret (32 bytes).
    case pairingSecret(Data, macName: String)
    case listRides(since: Date?)
    case rides([BridgeRide])
    case fetchRide(id: String)
    case rideData(id: String, fit: Data)
    case failure(String)
}

public enum BridgeError: Error, Equatable, Sendable {
    case notImplemented
    /// No bridge answered within the timeout (Mac asleep, other Wi-Fi, app closed).
    case unreachable
    /// TLS handshake failed: wrong code or stale secret.
    case authenticationFailed
    case protocolMismatch(Int)
    case malformedMessage
    case server(String)
}

/// Encoding of `BridgeMessage` into one frame payload (header handled by the framer).
public enum BridgeCodec {
    /// Wire type of a message (the framer's UInt32 header field).
    public static func type(of message: BridgeMessage) -> UInt32 {
        switch message {
        case .hello: BridgeWireType.hello
        case .welcome: BridgeWireType.welcome
        case .pairingSecret: BridgeWireType.pairingSecret
        case .listRides: BridgeWireType.listRides
        case .rides: BridgeWireType.rides
        case .fetchRide: BridgeWireType.fetchRide
        case .rideData: BridgeWireType.rideData
        case .failure: BridgeWireType.failure
        }
    }

    /// JSON payload (dates as seconds since 1970); `rideData` carries the raw FIT bytes behind a small id header.
    public static func encode(_ message: BridgeMessage) throws -> Data {
        let encoder = BridgeWire.makeEncoder()
        do {
            switch message {
            case .hello(let name, let version):
                return try encoder.encode(BridgeWire.Hello(deviceName: name, protocolVersion: version))
            case .welcome(let name, let version):
                return try encoder.encode(BridgeWire.Welcome(macName: name, protocolVersion: version))
            case .pairingSecret(let secret, let name):
                return try encoder.encode(BridgeWire.PairingSecret(secret: secret, macName: name))
            case .listRides(let since): return try encoder.encode(BridgeWire.ListRides(since: since))
            case .rides(let rides): return try encoder.encode(BridgeWire.Rides(rides: rides))
            case .fetchRide(let id): return try encoder.encode(BridgeWire.FetchRide(id: id))
            case .rideData(let id, let fit): return try BridgeWire.encodeRideData(id: id, fit: fit)
            case .failure(let text): return try encoder.encode(BridgeWire.Failure(message: text))
            }
        } catch let error as BridgeError {
            throw error
        } catch {
            throw BridgeError.malformedMessage
        }
    }

    public static func decode(type: UInt32, payload: Data) throws -> BridgeMessage {
        let decoder = BridgeWire.makeDecoder()
        do {
            switch type {
            case BridgeWireType.hello:
                let m = try decoder.decode(BridgeWire.Hello.self, from: payload)
                return .hello(deviceName: m.deviceName, protocolVersion: m.protocolVersion)
            case BridgeWireType.welcome:
                let m = try decoder.decode(BridgeWire.Welcome.self, from: payload)
                return .welcome(macName: m.macName, protocolVersion: m.protocolVersion)
            case BridgeWireType.pairingSecret:
                let m = try decoder.decode(BridgeWire.PairingSecret.self, from: payload)
                return .pairingSecret(m.secret, macName: m.macName)
            case BridgeWireType.listRides:
                return .listRides(since: try decoder.decode(BridgeWire.ListRides.self, from: payload).since)
            case BridgeWireType.rides:
                return .rides(try decoder.decode(BridgeWire.Rides.self, from: payload).rides)
            case BridgeWireType.fetchRide:
                return .fetchRide(id: try decoder.decode(BridgeWire.FetchRide.self, from: payload).id)
            case BridgeWireType.rideData:
                let (id, fit) = try BridgeWire.decodeRideData(payload)
                return .rideData(id: id, fit: fit)
            case BridgeWireType.failure:
                return .failure(try decoder.decode(BridgeWire.Failure.self, from: payload).message)
            default:
                throw BridgeError.malformedMessage
            }
        } catch let error as BridgeError {
            throw error
        } catch {
            throw BridgeError.malformedMessage
        }
    }
}

public enum BridgeCrypto {
    /// 6 random digits, e.g. "482913".
    public static func generatePairingCode() -> String {
        var generator = SystemRandomNumberGenerator()
        let value = Int.random(in: 0..<1_000_000, using: &generator)
        return String(format: "%06d", value)
    }
    /// 32 random bytes.
    public static func newPairingSecret() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            var generator = SystemRandomNumberGenerator()
            bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        }
        return Data(bytes)
    }
    /// TLS-PSK key derived from a pairing code (HKDF-SHA256, fixed salt/info), 32 bytes.
    public static func pairingKey(code: String) -> Data {
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: Data(code.utf8)),
                                         salt: Data("IndoorCoach-Bridge-v1".utf8), info: Data("pairing".utf8),
                                         outputByteCount: 32)
        return key.withUnsafeBytes { Data($0) }
    }
    /// TCP + TLS-PSK (TLS_PSK_WITH_AES_128_GCM_SHA256, negotiates TLS 1.2) + bridge framer. `identity` distinguishes pairing ("indoorcoach-pair") and main ("indoorcoach-bridge").
    public static func parameters(psk: Data, identity: String) -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()
        let options = tlsOptions.securityProtocolOptions
        sec_protocol_options_add_pre_shared_key(options, dispatchData(psk) as __DispatchData,
                                                dispatchData(Data(identity.utf8)) as __DispatchData)
        sec_protocol_options_append_tls_ciphersuite(options, tls_ciphersuite_t(rawValue: TLS_PSK_WITH_AES_128_GCM_SHA256)!)
        let parameters = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
        parameters.defaultProtocolStack.applicationProtocols.insert(
            NWProtocolFramer.Options(definition: BridgeFramer.definition), at: 0)
        return parameters
    }

    private static func dispatchData(_ data: Data) -> DispatchData {
        data.withUnsafeBytes { DispatchData(bytes: $0) }
    }
    public static let mainIdentity = "indoorcoach-bridge"
    public static let pairingIdentity = "indoorcoach-pair"
}

/// What the server serves. Implemented by `BridgeOutbox` on the Mac; tests use an in-memory source.
public protocol BridgeRideSource: Sendable {
    func rides(since: Date?) async -> [BridgeRide]
    func fitData(id: String) async -> Data?
}

/// macOS side: advertises the rides via Bonjour. Also compiles on iOS (used in tests only).
public final class BridgeServer: @unchecked Sendable {
    public struct Event: Sendable, Equatable {
        public enum Kind: Sendable, Equatable { case connected, listed(Int), fetched(String), paired }
        public var deviceName: String
        public var kind: Kind
    }

    private let core: BridgeServerCore

    /// `advertise: false` for loopback tests (connect via `port`).
    public init(name: String, secret: Data, source: any BridgeRideSource, advertise: Bool = true) {
        core = BridgeServerCore(name: name, secret: secret, source: source, advertise: advertise)
    }
    /// Called on the server's internal queue.
    public var onEvent: (@Sendable (Event) -> Void)? {
        get { core.onEvent }
        set { core.onEvent = newValue }
    }
    /// Port of the main listener once started (nil before).
    public var port: UInt16? { core.port }
    /// Port of the pairing listener while pairing (nil otherwise).
    public var pairingPort: UInt16? { core.pairingPort }
    public func start() async throws { try await core.start() }
    public func stop() { core.stop() }
    /// Opens the pairing listener for `Bridge.pairingWindow`; closes after the first successful pairing.
    public func startPairing(code: String) async throws { try await core.startPairing(code: code) }
    public func stopPairing() { core.stopPairing() }
    /// Replaces the secret (reset pairing): existing phones must pair again.
    public func updateSecret(_ secret: Data) { core.updateSecret(secret) }
}

public struct DiscoveredBridge: Hashable, Sendable, Identifiable {
    public var name: String
    public var endpoint: NWEndpoint
    public var id: String { name }
    public init(name: String, endpoint: NWEndpoint) {
        self.name = name
        self.endpoint = endpoint
    }
}

/// iOS side.
public actor BridgeClient {
    private let deviceName: String
    public init(deviceName: String) { self.deviceName = deviceName }
    /// Browses `Bridge.serviceType` (or the pairing service) for up to `timeout`.
    public func discover(pairing: Bool, timeout: Duration = .seconds(4)) async -> [DiscoveredBridge] {
        await BridgeBrowse.discover(type: pairing ? Bridge.pairingServiceType : Bridge.serviceType, timeout: timeout)
    }
    /// Pairs with a bridge showing `code`. Returns the long secret and the Mac's name.
    public func pair(with bridge: DiscoveredBridge, code: String) async throws -> (secret: Data, macName: String) {
        let channel = BridgeBrowse.channel(to: bridge.endpoint, psk: BridgeCrypto.pairingKey(code: code),
                                           identity: BridgeCrypto.pairingIdentity)
        defer { channel.cancel() }
        try await channel.start(timeout: 8)
        let answer = try await channel.request(.hello(deviceName: deviceName, protocolVersion: Bridge.protocolVersion),
                                               timeout: 8)
        guard case .pairingSecret(let secret, let macName) = answer else { throw BridgeError.malformedMessage }
        Log.notice(.bridge, "paired with a bridge")
        return (secret, macName)
    }
    /// Lists the bridge's rides and downloads those whose id is not in `known`. Order: oldest first.
    public func fetchNewRides(from bridge: DiscoveredBridge, secret: Data, since: Date?, known: Set<String>,
                              limit: Int = 200) async throws -> [(ride: BridgeRide, fit: Data)] {
        let channel = BridgeBrowse.channel(to: bridge.endpoint, psk: secret, identity: BridgeCrypto.mainIdentity)
        defer { channel.cancel() }
        try await channel.start(timeout: 8)
        let welcome = try await channel.request(.hello(deviceName: deviceName, protocolVersion: Bridge.protocolVersion),
                                                timeout: 8)
        guard case .welcome(_, let version) = welcome else { throw BridgeError.malformedMessage }
        guard version == Bridge.protocolVersion else { throw BridgeError.protocolMismatch(version) }
        guard case .rides(let all) = try await channel.request(.listRides(since: since), timeout: 15) else {
            throw BridgeError.malformedMessage
        }
        let wanted = all.filter { !known.contains($0.id) }.sorted { $0.startDate < $1.startDate }.prefix(max(0, limit))
        var result: [(ride: BridgeRide, fit: Data)] = []
        for ride in wanted {
            guard case .rideData(let id, let fit) = try await channel.request(.fetchRide(id: ride.id), timeout: 30),
                  id == ride.id else { throw BridgeError.malformedMessage }
            result.append((ride, fit))
        }
        Log.notice(.bridge, "fetched \(result.count) of \(all.count) rides")
        return result
    }
}

/// Pure decision logic for the watched folder: a file is ready once its size and modification date stayed the
/// same over two scans and it is at least `minimumAge` old. Each (path, size, mtime) is reported once.
public struct RideFolderScanner: Sendable {
    public struct FileInfo: Hashable, Sendable {
        public var url: URL
        public var size: Int
        public var modified: Date
        public init(url: URL, size: Int, modified: Date) {
            self.url = url
            self.size = size
            self.modified = modified
        }
    }

    public var minimumAge: TimeInterval
    private struct Signature: Equatable { var size: Int; var modified: Date }
    private var previous: [URL: Signature] = [:]
    private var reported: [URL: Signature] = [:]
    public init(minimumAge: TimeInterval = 15) { self.minimumAge = minimumAge }
    /// Feed the current listing (only `.fit` files, case-insensitive); returns the files to import now.
    public mutating func ready(_ files: [FileInfo], now: Date) -> [FileInfo] {
        var result: [FileInfo] = []
        var current: [URL: Signature] = [:]
        for file in files {
            let signature = Signature(size: file.size, modified: file.modified)
            current[file.url] = signature
            if reported[file.url] == signature { continue }
            if previous[file.url] == signature, now.timeIntervalSince(file.modified) >= minimumAge {
                reported[file.url] = signature
                result.append(file)
            }
        }
        previous = current
        reported = reported.filter { current[$0.key] != nil }
        return result
    }
    /// `.fit` files directly in `folder` (not recursive).
    public static func listFITFiles(in folder: URL) -> [FileInfo] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                 options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { url in
            guard url.pathExtension.lowercased() == "fit",
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let size = values.fileSize, let modified = values.contentModificationDate else { return nil }
            return FileInfo(url: url, size: size, modified: modified)
        }.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }
    /// `~/Library/Containers/com.whoosh.whooshgame/Data/Library/Application Support/Epic/MyWhoosh/Content/Data`
    public static func myWhooshFolder(home: URL) -> URL {
        home.appending(path: "Library/Containers/com.whoosh.whooshgame/Data/Library/Application Support/Epic/MyWhoosh/Content/Data",
                       directoryHint: .isDirectory)
    }
}

/// The bridge's own copy of every ride (MyWhoosh may overwrite its file): `<dir>/fit-<start>.fit` + index.json.
public final class BridgeOutbox: BridgeRideSource, @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()
    private var index: [BridgeRide] = []

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
           let rides = try? BridgeWire.makeDecoder().decode([BridgeRide].self, from: data) {
            index = rides
        }
    }

    private var indexURL: URL { directory.appending(path: "index.json") }
    private func fileURL(_ id: String) -> URL { directory.appending(path: "\(id).fit") }

    private func saveIndex() {
        if let data = try? BridgeWire.makeEncoder().encode(index) { try? data.write(to: indexURL, options: .atomic) }
    }

    /// Parses the FIT file (must be a readable activity), stores it, returns the ride; nil when unreadable.
    /// A file with an already known start replaces nothing and returns the existing ride.
    @discardableResult
    public func add(fit: Data, addedAt: Date = .now) throws -> BridgeRide? {
        guard let summary = try? FITParser.summary(from: fit) else { return nil }
        let id = BridgeRide.id(forStart: summary.startDate)
        return lock.withLock {
            if let existing = index.first(where: { $0.id == id }) { return existing }
            do { try fit.write(to: fileURL(id), options: .atomic) } catch { return nil }
            let ride = BridgeRide(id: id, startDate: summary.startDate, durationSeconds: summary.movingTime,
                                  byteCount: fit.count, addedAt: addedAt)
            index.append(ride)
            saveIndex()
            return ride
        }
    }
    public var count: Int { lock.withLock { index.count } }
    public var latest: BridgeRide? { lock.withLock { index.max { $0.startDate < $1.startDate } } }
    public func rides(since: Date?) async -> [BridgeRide] {
        lock.withLock {
            index.filter { since == nil || $0.addedAt > since! }.sorted { $0.startDate < $1.startDate }
        }
    }
    public func fitData(id: String) async -> Data? {
        // Only ids from the index reach the file system (the id comes from the network).
        guard lock.withLock({ index.contains { $0.id == id } }) else { return nil }
        return try? Data(contentsOf: fileURL(id))
    }
    /// Removes rides started before `now - days`.
    public func prune(keepDays: Int = 180, now: Date = .now) {
        let cutoff = now.addingTimeInterval(-Double(keepDays) * 86_400)
        lock.withLock {
            let old = index.filter { $0.startDate < cutoff }
            guard !old.isEmpty else { return }
            for ride in old { try? FileManager.default.removeItem(at: fileURL(ride.id)) }
            index.removeAll { $0.startDate < cutoff }
            saveIndex()
        }
    }
}
