import Foundation
import Network
import Observation
import SwiftData

// IndoorCoach Brücke, iPhone side (docs/14-SEKUNDENDATEN-MAC-BRUECKE.md): pairing, pickup of the Mac's FIT files,
// enrichment of stored rides. The secret lives only in the Keychain (`Keychain.Key.bridgeSecret`) and is never logged.

/// What the iPhone needs from the transport. `LiveBridgeTransport` wraps `BridgeClient`; tests and the UI-test
/// stub (`-uiBridgeStub YES`, DEBUG) provide their own.
public protocol BridgeTransport: Sendable {
    /// Bridges in the Wi-Fi; `pairing: true` finds Macs that currently show a code.
    func discover(pairing: Bool) async -> [DiscoveredBridge]
    func pair(with bridge: DiscoveredBridge, code: String) async throws -> (secret: Data, macName: String)
    /// Finds the paired Mac by name and downloads the rides whose id is not in `known` (oldest first).
    func fetchNewRides(macName: String, secret: Data, known: Set<String>) async throws -> [(ride: BridgeRide, fit: Data)]
}

public struct LiveBridgeTransport: BridgeTransport {
    private let client = BridgeClient(deviceName: "iPhone")
    /// DEBUG end-to-end tests without Bonjour (`-uiBridgeEndpoint host:mainPort:pairingPort`): fixed endpoints.
    private let direct: (host: String, main: UInt16, pairing: UInt16)?

    public init() { direct = nil }

    #if DEBUG
    init(directHost host: String, mainPort: UInt16, pairingPort: UInt16) { direct = (host, mainPort, pairingPort) }
    #endif

    public func discover(pairing: Bool) async -> [DiscoveredBridge] {
        if let direct, let port = NWEndpoint.Port(rawValue: pairing ? direct.pairing : direct.main) {
            return [DiscoveredBridge(name: "Mac (direkt)", endpoint: .hostPort(host: .init(direct.host), port: port))]
        }
        return await client.discover(pairing: pairing, timeout: .seconds(3))
    }

    public func pair(with bridge: DiscoveredBridge, code: String) async throws -> (secret: Data, macName: String) {
        try await client.pair(with: bridge, code: code)
    }

    public func fetchNewRides(macName: String, secret: Data, known: Set<String>) async throws -> [(ride: BridgeRide, fit: Data)] {
        let found = direct != nil ? await discover(pairing: false) : await client.discover(pairing: false, timeout: .seconds(4))
        guard let mac = found.first(where: { $0.name == macName }) ?? (found.count == 1 ? found.first : nil) else {
            throw BridgeError.unreachable
        }
        return try await client.fetchNewRides(from: mac, secret: secret, since: nil, known: known)
    }
}

/// Observable bridge state (a nested object so `AppModel` itself only gains one stored property).
@MainActor
@Observable
public final class BridgeState {
    public internal(set) var macName: String?
    public internal(set) var lastSync: Date?
    public internal(set) var syncing = false
    @ObservationIgnored var knownIDs: Set<String> = []
    @ObservationIgnored var lastAttempt: Date?
    @ObservationIgnored var transport: any BridgeTransport = LiveBridgeTransport()

    #if DEBUG
    @ObservationIgnored var isStub = false
    @ObservationIgnored var seeded = false
    #endif

    nonisolated init() {}

    func load(defaults: UserDefaults) {
        macName = defaults.string(forKey: AppModel.Keys.bridgeMacName)
        lastSync = defaults.object(forKey: AppModel.Keys.bridgeLastSync) as? Date
        knownIDs = Set(defaults.stringArray(forKey: AppModel.Keys.bridgeKnownIDs) ?? [])
    }

    func reset() {
        macName = nil
        lastSync = nil
        syncing = false
        knownIDs = []
        lastAttempt = nil
    }
}

/// Counts of one pickup, shown after pairing and in the banner.
public struct BridgeSyncSummary: Equatable, Sendable {
    public var received = 0
    public var inserted = 0
    public var enriched = 0
    public var unreadable = 0
}

extension AppModel {
    /// Auto pickups (app start / foreground) run at most this often.
    static let bridgeAutoInterval: TimeInterval = 120

    public var bridgeMacName: String? { bridge.macName }
    public var isBridgePaired: Bool { bridge.macName != nil && secrets.secret(.bridgeSecret) != nil }
    public var lastBridgeSync: Date? { bridge.lastSync }
    public var bridgeSyncing: Bool { bridge.syncing }

    /// Rides with measured 1 Hz data versus all rides ("14 von 14 Fahrten mit Sekundendaten").
    public func secondsCoverage() -> (measured: Int, total: Int) {
        let total = (try? context.fetchCount(FetchDescriptor<StoredRide>())) ?? 0
        let measured = (try? context.fetchCount(FetchDescriptor<StoredRide>(predicate: #Predicate { $0.powerCurveData != nil }))) ?? 0
        return (measured, total)
    }

    // MARK: Discovery & pairing

    public func discoverBridges() async -> [DiscoveredBridge] {
        await bridge.transport.discover(pairing: true)
    }

    /// Pairs with the Mac showing `code`, stores the secret in the Keychain and does the first pickup.
    /// Throws `BridgeError` (`.authenticationFailed` for a wrong code) – nothing is stored then.
    public func pairBridge(_ mac: DiscoveredBridge, code: String) async throws -> BridgeSyncSummary {
        let result = try await bridge.transport.pair(with: mac, code: code)
        secrets.setSecret(result.secret.base64EncodedString(), for: .bridgeSecret)
        bridge.macName = result.macName
        defaults.set(result.macName, forKey: Keys.bridgeMacName)
        bridge.knownIDs = []
        defaults.removeObject(forKey: Keys.bridgeKnownIDs)
        syncErrors[.macBridge] = nil
        Log.notice(.bridge, "Mac-Brücke gekoppelt")
        return await pickUpFromBridge(announce: true, quietUnreachable: true) ?? BridgeSyncSummary()
    }

    /// "Kopplung lösen": forgets the secret and the paired Mac on this iPhone (rides stay).
    public func unpairBridge() {
        secrets.setSecret(nil, for: .bridgeSecret)
        defaults.removeObject(forKey: Keys.bridgeMacName)
        defaults.removeObject(forKey: Keys.bridgeLastSync)
        defaults.removeObject(forKey: Keys.bridgeKnownIDs)
        bridge.reset()
        syncErrors[.macBridge] = nil
        Log.notice(.bridge, "Kopplung gelöst")
        show("Kopplung mit dem Mac gelöst. Deine Fahrten bleiben erhalten.", error: false)
    }

    // MARK: Pickup

    /// Fetches new rides from the paired Mac. `announce: false` is the automatic run (foreground, at most every
    /// 2 minutes, silent when the Mac is unreachable); `true` is "Jetzt abholen" and reports every outcome.
    @discardableResult
    public func syncFromBridge(announce: Bool) async -> BridgeSyncSummary? {
        await pickUpFromBridge(announce: announce, quietUnreachable: false)
    }

    private func pickUpFromBridge(announce: Bool, quietUnreachable: Bool) async -> BridgeSyncSummary? {
        guard isBridgePaired, !bridge.syncing, let macName = bridge.macName,
              let secretText = secrets.secret(.bridgeSecret), let secret = Data(base64Encoded: secretText) else { return nil }
        if !announce, let last = bridge.lastAttempt, Date.now.timeIntervalSince(last) < Self.bridgeAutoInterval { return nil }
        bridge.lastAttempt = .now
        bridge.syncing = true
        defer { bridge.syncing = false }
        let started = ContinuousClock.now
        do {
            let fetched = try await bridge.transport.fetchNewRides(macName: macName, secret: secret, known: bridge.knownIDs)
            var summary = BridgeSyncSummary(received: fetched.count)
            var rides: [RideSummary] = []
            var seconds: [Int: RideSeconds] = [:]
            for item in fetched {
                if let fit = try? FITParser.summary(from: item.fit) {
                    let id = Self.importedRideID("fit:\(Int(fit.startDate.timeIntervalSince1970))")
                    rides.append(RideSummary(fit: fit, id: id, name: "MyWhoosh-Fahrt"))
                    if let s = fit.seconds { seconds[id] = s }
                } else {
                    summary.unreadable += 1
                }
                bridge.knownIDs.insert(item.ride.id)      // an unreadable file would fail again – do not refetch it
            }
            let result = mergeImportedRides(rides, seconds: seconds)
            summary.inserted = result.inserted
            summary.enriched = result.enriched
            bridge.lastSync = .now
            defaults.set(bridge.lastSync, forKey: Keys.bridgeLastSync)
            defaults.set(Array(bridge.knownIDs), forKey: Keys.bridgeKnownIDs)
            Log.notice(.bridge, "Abgleich: \(summary.received) geladen, \(summary.inserted) neu, \(summary.enriched) ergänzt, \(summary.unreadable) unlesbar, \(Self.elapsed(since: started))")
            syncErrors[.macBridge] = nil
            if let message = Self.bridgeBanner(summary, newest: result.lastInserted, announce: announce) { show(message, error: false) }
            return summary
        } catch let error as BridgeError {
            Log.error(.bridge, "Abgleich fehlgeschlagen: \(error)")
            switch error {
            case .unreachable:
                if announce && !quietUnreachable {
                    syncErrors[.macBridge] = "Mac nicht erreichbar."
                    show(Self.bridgeUnreachableMessage, error: true)
                }
            case .authenticationFailed:
                // Dauerhaft (bis neu gekoppelt): auch der stille Auto-Lauf setzt den Status, nur das Banner bleibt aus.
                syncErrors[.macBridge] = "Kopplung erneuern – sie passt nicht mehr."
                if announce {
                    show("Die Kopplung passt nicht mehr. Löse sie und koppele den Mac neu.", error: true)
                }
            default:
                if announce {
                    syncErrors[.macBridge] = "Abgleich fehlgeschlagen."
                    show("Der Abgleich mit dem Mac ist fehlgeschlagen.", error: true)
                }
            }
            return nil
        } catch {
            Log.error(.bridge, "Abgleich fehlgeschlagen: \(type(of: error))")
            if announce {
                syncErrors[.macBridge] = "Abgleich fehlgeschlagen."
                show("Der Abgleich mit dem Mac ist fehlgeschlagen.", error: true)
            }
            return nil
        }
    }

    static let bridgeUnreachableMessage = "Mac nicht erreichbar – ist die Brücke geöffnet und seid ihr im selben WLAN?"

    /// "Neue Fahrt vom Mac: 52 min · NP 214 W" for one new ride, otherwise "Vom Mac: 3 neu, 12 ergänzt".
    static func bridgeBanner(_ summary: BridgeSyncSummary, newest: RideSummary?, announce: Bool) -> String? {
        if summary.inserted == 1, summary.enriched == 0, let ride = newest {
            var text = "Neue Fahrt vom Mac: \(Formatters.duration(ride.movingTime))"
            if let np = ride.weightedAverageWatts ?? ride.averageWatts { text += " · NP \(Int(np.rounded())) W" }
            return text
        }
        var parts: [String] = []
        if summary.inserted > 0 { parts.append("\(summary.inserted) neu") }
        if summary.enriched > 0 { parts.append("\(summary.enriched) ergänzt") }
        if !parts.isEmpty { return "Vom Mac: " + parts.joined(separator: ", ") }
        return announce ? "Keine neuen Fahrten auf dem Mac." : nil
    }
}

#if DEBUG
// MARK: - UI-test stub (`-uiBridgeStub YES`)

/// One Mac "Lenas MacBook Air", code 482913. The first pickup brings three rides (one starts within 5 minutes of a
/// stored ride and enriches it), later pickups one more new ride. Real FIT bytes go through the normal parser.
final class StubBridgeTransport: BridgeTransport, @unchecked Sendable {
    static let macName = "Lenas MacBook Air"
    static let code = "482913"
    private let anchor: @Sendable () async -> Date?
    private let lock = NSLock()
    private var calls = 0

    init(anchor: @escaping @Sendable () async -> Date?) { self.anchor = anchor }

    func discover(pairing: Bool) async -> [DiscoveredBridge] {
        try? await Task.sleep(for: .milliseconds(400))
        let endpoint = NWEndpoint.service(name: Self.macName, type: pairing ? Bridge.pairingServiceType : Bridge.serviceType,
                                          domain: "local.", interface: nil)
        return [DiscoveredBridge(name: Self.macName, endpoint: endpoint)]
    }

    func pair(with bridge: DiscoveredBridge, code: String) async throws -> (secret: Data, macName: String) {
        try? await Task.sleep(for: .milliseconds(500))
        guard code == Self.code else { throw BridgeError.authenticationFailed }
        return (Data((0..<32).map { _ in UInt8.random(in: 0...255) }), Self.macName)
    }

    func fetchNewRides(macName: String, secret: Data, known: Set<String>) async throws -> [(ride: BridgeRide, fit: Data)] {
        try? await Task.sleep(for: .milliseconds(500))
        let call = lock.withLock { calls += 1; return calls }
        let now = Date.now
        let day = Calendar.current.startOfDay(for: now)
        func at(_ daysAgo: Int, hour: Int, minute: Int) -> Date {
            Calendar.current.date(bySettingHour: hour, minute: minute, second: 0,
                                  of: Calendar.current.date(byAdding: .day, value: -daysAgo, to: day)!)!
        }
        var specs: [(start: Date, minutes: Int, watts: Int)] = []
        if let anchorStart = await anchor() { specs.append((anchorStart.addingTimeInterval(120), 62, 196)) }
        specs.append((at(4, hour: 12, minute: 17), 48, 205))
        specs.append((at(6, hour: 12, minute: 41), 75, 188))
        if call >= 2 { specs.append((now.addingTimeInterval(-70 * 60), 52, 214)) }
        let offered = specs.map { spec -> (ride: BridgeRide, fit: Data) in
            let fit = Self.fit(start: spec.start, minutes: spec.minutes, watts: spec.watts)
            let ride = BridgeRide(id: BridgeRide.id(forStart: spec.start), startDate: spec.start,
                                  durationSeconds: spec.minutes * 60, byteCount: fit.count, addedAt: now)
            return (ride, fit)
        }
        return offered.filter { !known.contains($0.ride.id) }
    }

    /// A small FIT file: session summary plus one record per second (alternating blocks, so the curve is not flat).
    static func fit(start: Date, minutes: Int, watts: Int) -> Data {
        var body: [UInt8] = []
        func define(global: UInt16, fields: [(UInt8, Int)]) {
            body += [0x40, 0, 0, UInt8(global & 0xFF), UInt8(global >> 8), UInt8(fields.count)]
            for f in fields { body += [f.0, UInt8(f.1), f.1 == 1 ? 0x02 : f.1 == 2 ? 0x84 : 0x86] }
        }
        func data(_ values: [(Int, UInt64)]) {
            body.append(0)
            for (size, value) in values { for b in 0..<size { body.append(UInt8((value >> (8 * UInt64(b))) & 0xFF)) } }
        }
        let t0 = UInt64(start.timeIntervalSince1970 - FITParser.fitEpoch)
        let seconds = minutes * 60
        define(global: 18, fields: [(2, 4), (8, 4), (9, 4), (20, 2), (34, 2), (16, 1), (17, 1), (48, 4)])
        data([(4, t0), (4, UInt64(seconds * 1000)), (4, UInt64(minutes * 52_000)), (2, UInt64(Double(watts) * 0.95)),
              (2, UInt64(watts)), (1, 138), (1, 171), (4, UInt64(watts * seconds))])
        define(global: 20, fields: [(253, 4), (7, 2), (3, 1)])
        for s in 0..<seconds {
            let block = (s / 300) % 2 == 0 ? 0.88 : 1.12
            data([(4, t0 + UInt64(s)), (2, UInt64(Double(watts) * block)), (1, UInt64(128 + (s / 600) % 5 * 3))])
        }
        let size = UInt32(body.count)
        let header: [UInt8] = [14, 0x20, 0x08, 0x08, UInt8(size & 0xFF), UInt8(size >> 8 & 0xFF), UInt8(size >> 16 & 0xFF),
                               UInt8(size >> 24), 0x2E, 0x46, 0x49, 0x54, 0, 0]
        return Data(header + body + [0, 0])
    }
}

extension AppModel {
    /// `-uiBridgeEndpoint 127.0.0.1:64579:64580`: the real transport, but without Bonjour (end-to-end test against a
    /// running bridge from the simulator while macOS has not yet allowed the bridge to advertise).
    func installDirectBridgeEndpoint(_ spec: String) {
        let parts = spec.split(separator: ":").map(String.init)
        guard parts.count == 3, let main = UInt16(parts[1]), let pairing = UInt16(parts[2]) else { return }
        bridge.transport = LiveBridgeTransport(directHost: parts[0], mainPort: main, pairingPort: pairing)
    }

    /// Swaps in the stub transport. Called by `AppEnvironment.makeModel` for `-uiBridgeStub YES`.
    func installBridgeStub() {
        bridge.isStub = true
        bridge.transport = StubBridgeTransport(anchor: { [weak self] in await MainActor.run { self?.newestRideStart() } })
    }

    private func newestRideStart() -> Date? {
        var d = FetchDescriptor<StoredRide>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first?.startDate
    }

    /// With the stub: the eight newest rides become "real" rides without seconds data (as if they came from the
    /// MyWhoosh list), so the coverage card, the pairing and the enrichment can be exercised. Idempotent per launch.
    func applyBridgeStubSeed() {
        guard bridge.isStub, !bridge.seeded else { return }
        bridge.seeded = true
        guard let rides = try? context.fetch(FetchDescriptor<StoredRide>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])),
              !rides.isEmpty, rides.allSatisfy(\.isDemo) else { return }
        let kept: [RideSummary] = rides.prefix(8).map { stored in
            var r = stored.summary
            r.powerCurve = nil
            r.maxWatts = nil
            r.decoupling = nil
            r.durability = nil
            return r
        }
        try? context.delete(model: StoredRide.self)
        try? context.save()
        mergeImportedRides(kept)
    }
}
#endif
