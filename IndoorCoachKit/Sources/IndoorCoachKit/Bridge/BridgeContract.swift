import Foundation
import Network

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
    public static func type(of message: BridgeMessage) -> UInt32 { 0 }
    public static func encode(_ message: BridgeMessage) throws -> Data { throw BridgeError.notImplemented }
    public static func decode(type: UInt32, payload: Data) throws -> BridgeMessage { throw BridgeError.notImplemented }
}

public enum BridgeCrypto {
    /// 6 random digits, e.g. "482913".
    public static func generatePairingCode() -> String { "000000" }
    /// 32 random bytes.
    public static func newPairingSecret() -> Data { Data(count: 32) }
    /// TLS-PSK key derived from a pairing code (HKDF-SHA256, fixed salt/info), 32 bytes.
    public static func pairingKey(code: String) -> Data { Data(count: 32) }
    /// TCP + TLS 1.3 (PSK) + bridge framer. `identity` distinguishes pairing ("indoorcoach-pair") and main ("indoorcoach-bridge").
    public static func parameters(psk: Data, identity: String) -> NWParameters { .tcp }
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

    /// `advertise: false` for loopback tests (connect via `port`).
    public init(name: String, secret: Data, source: any BridgeRideSource, advertise: Bool = true) {}
    /// Called on the server's internal queue.
    public var onEvent: (@Sendable (Event) -> Void)?
    /// Port of the main listener once started (nil before).
    public var port: UInt16? { nil }
    /// Port of the pairing listener while pairing (nil otherwise).
    public var pairingPort: UInt16? { nil }
    public func start() async throws { throw BridgeError.notImplemented }
    public func stop() {}
    /// Opens the pairing listener for `Bridge.pairingWindow`; closes after the first successful pairing.
    public func startPairing(code: String) async throws { throw BridgeError.notImplemented }
    public func stopPairing() {}
    /// Replaces the secret (reset pairing): existing phones must pair again.
    public func updateSecret(_ secret: Data) {}
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
    public init(deviceName: String) {}
    /// Browses `Bridge.serviceType` (or the pairing service) for up to `timeout`.
    public func discover(pairing: Bool, timeout: Duration = .seconds(4)) async -> [DiscoveredBridge] { [] }
    /// Pairs with a bridge showing `code`. Returns the long secret and the Mac's name.
    public func pair(with bridge: DiscoveredBridge, code: String) async throws -> (secret: Data, macName: String) {
        throw BridgeError.notImplemented
    }
    /// Lists the bridge's rides and downloads those whose id is not in `known`. Order: oldest first.
    public func fetchNewRides(from bridge: DiscoveredBridge, secret: Data, since: Date?, known: Set<String>,
                              limit: Int = 200) async throws -> [(ride: BridgeRide, fit: Data)] {
        throw BridgeError.notImplemented
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
    public init(minimumAge: TimeInterval = 15) { self.minimumAge = minimumAge }
    /// Feed the current listing (only `.fit` files, case-insensitive); returns the files to import now.
    public mutating func ready(_ files: [FileInfo], now: Date) -> [FileInfo] { [] }
    /// `.fit` files directly in `folder` (not recursive).
    public static func listFITFiles(in folder: URL) -> [FileInfo] { [] }
    /// `~/Library/Containers/com.whoosh.whooshgame/Data/Library/Application Support/Epic/MyWhoosh/Content/Data`
    public static func myWhooshFolder(home: URL) -> URL {
        home.appending(path: "Library/Containers/com.whoosh.whooshgame/Data/Library/Application Support/Epic/MyWhoosh/Content/Data",
                       directoryHint: .isDirectory)
    }
}

/// The bridge's own copy of every ride (MyWhoosh may overwrite its file): `<dir>/fit-<start>.fit` + index.json.
public final class BridgeOutbox: BridgeRideSource, @unchecked Sendable {
    public init(directory: URL) {}
    /// Parses the FIT file (must be a readable activity), stores it, returns the ride; nil when unreadable.
    /// A file with an already known start replaces nothing and returns the existing ride.
    @discardableResult
    public func add(fit: Data, addedAt: Date = .now) throws -> BridgeRide? { throw BridgeError.notImplemented }
    public var count: Int { 0 }
    public var latest: BridgeRide? { nil }
    public func rides(since: Date?) async -> [BridgeRide] { [] }
    public func fitData(id: String) async -> Data? { nil }
    /// Removes rides started before `now - days`.
    public func prune(keepDays: Int = 180, now: Date = .now) {}
}
