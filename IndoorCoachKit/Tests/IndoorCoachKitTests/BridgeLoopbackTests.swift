import Foundation
import Network
import Testing
@testable import IndoorCoachKit

private struct MemorySource: BridgeRideSource {
    var items: [(BridgeRide, Data)]
    func rides(since: Date?) async -> [BridgeRide] { items.map(\.0).filter { since == nil || $0.addedAt > since! } }
    func fitData(id: String) async -> Data? { items.first { $0.0.id == id }?.1 }
}

private func makeSource() -> MemorySource {
    let base = Date(timeIntervalSince1970: 1_794_000_000)
    let items = (0..<3).map { i -> (BridgeRide, Data) in
        let start = base.addingTimeInterval(Double(i) * 86_400)
        let data = Data((0..<(3_000 + i)).map { UInt8($0 % 251) })
        return (BridgeRide(id: BridgeRide.id(forStart: start), startDate: start, durationSeconds: 3_600,
                           byteCount: data.count, addedAt: base.addingTimeInterval(Double(i) * 10)), data)
    }
    // Deliberately unordered: the client must sort oldest first.
    return MemorySource(items: [items[2], items[0], items[1]])
}

private func local(_ port: UInt16?) throws -> DiscoveredBridge {
    let port = try #require(port)
    return DiscoveredBridge(name: "x", endpoint: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!))
}

@Suite("Bridge loopback", .serialized, .timeLimit(.minutes(1)))
struct BridgeLoopbackTests {
    @Test func fetchesNewRidesOldestFirst() async throws {
        let source = makeSource()
        let secret = BridgeCrypto.newPairingSecret()
        let server = BridgeServer(name: "Test-Mac", secret: secret, source: source, advertise: false)
        try await server.start()
        defer { server.stop() }
        let bridge = try local(server.port)
        let client = BridgeClient(deviceName: "Test-Phone")

        let fetched = try await client.fetchNewRides(from: bridge, secret: secret, since: nil, known: [])
        #expect(fetched.count == 3)
        #expect(fetched.map(\.ride.startDate) == fetched.map(\.ride.startDate).sorted())
        for (ride, fit) in fetched { #expect(fit == source.items.first { $0.0.id == ride.id }?.1) }

        let known: Set<String> = [fetched[0].ride.id]
        let limited = try await client.fetchNewRides(from: bridge, secret: secret, since: nil, known: known, limit: 1)
        #expect(limited.map(\.ride.id) == [fetched[1].ride.id])
        let since = try await client.fetchNewRides(from: bridge, secret: secret, since: fetched[1].ride.addedAt, known: [])
        #expect(since.map(\.ride.id) == [fetched[2].ride.id])
    }

    @Test func wrongSecretFailsWithoutHanging() async throws {
        let server = BridgeServer(name: "Mac", secret: BridgeCrypto.newPairingSecret(), source: makeSource(), advertise: false)
        try await server.start()
        defer { server.stop() }
        let client = BridgeClient(deviceName: "Phone")
        let bridge = try local(server.port)
        await #expect(throws: BridgeError.authenticationFailed) {
            _ = try await client.fetchNewRides(from: bridge, secret: BridgeCrypto.newPairingSecret(), since: nil, known: [])
        }
    }

    @Test func pairingReturnsTheSecretAndClosesAfterwards() async throws {
        let secret = BridgeCrypto.newPairingSecret()
        let server = BridgeServer(name: "Mein Mac", secret: secret, source: makeSource(), advertise: false)
        try await server.start()
        defer { server.stop() }
        #expect(server.pairingPort == nil)
        let events = EventBox()
        server.onEvent = { events.add($0) }
        try await server.startPairing(code: "012345")
        let bridge = try local(server.pairingPort)
        let client = BridgeClient(deviceName: "Phone")

        await #expect(throws: BridgeError.self) { _ = try await client.pair(with: bridge, code: "999999") }
        #expect(server.pairingPort != nil) // a failed attempt does not consume the window

        let result = try await client.pair(with: bridge, code: "012345")
        #expect(result.secret == secret)
        #expect(result.macName == "Mein Mac")
        try await Task.sleep(for: .milliseconds(300))
        #expect(server.pairingPort == nil)
        #expect(events.all.contains(.init(deviceName: "Phone", kind: .paired)))
    }

    @Test func emitsEventsAndRejectsUnknownRides() async throws {
        let source = makeSource()
        let secret = BridgeCrypto.newPairingSecret()
        let server = BridgeServer(name: "Mac", secret: secret, source: source, advertise: false)
        let events = EventBox()
        server.onEvent = { events.add($0) }
        try await server.start()
        defer { server.stop() }
        _ = try await BridgeClient(deviceName: "Phone")
            .fetchNewRides(from: try local(server.port), secret: secret, since: nil, known: [])
        try await Task.sleep(for: .milliseconds(200))
        let kinds = events.all.map(\.kind)
        #expect(kinds.contains(.connected) && kinds.contains(.listed(3)))
        #expect(kinds.filter { if case .fetched = $0 { true } else { false } }.count == 3)
    }

    @Test func nothingListeningIsUnreachable() async throws {
        let server = BridgeServer(name: "Mac", secret: BridgeCrypto.newPairingSecret(), source: makeSource(), advertise: false)
        try await server.start()
        let bridge = try local(server.port)
        server.stop()
        try await Task.sleep(for: .milliseconds(200))
        await #expect(throws: BridgeError.self) {
            _ = try await BridgeClient(deviceName: "P").fetchNewRides(from: bridge, secret: Data(count: 32), since: nil, known: [])
        }
    }
}

private final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [BridgeServer.Event] = []
    func add(_ e: BridgeServer.Event) { lock.withLock { events.append(e) } }
    var all: [BridgeServer.Event] { lock.withLock { events } }
}

@Suite("Bridge connection end", .serialized, .timeLimit(.minutes(1)))
struct BridgeConnectionEndTests {
    /// A phone that fetched and closed the connection is a normal end, not a malformed message (log hygiene: the
    /// server's log should not report an error after every successful pickup).
    @Test func cleanCloseIsNotReportedAsMalformed() async throws {
        let secret = BridgeCrypto.newPairingSecret()
        let server = BridgeServer(name: "Mac", secret: secret, source: makeSource(), advertise: false)
        try await server.start()
        defer { server.stop() }
        _ = try await BridgeClient(deviceName: "Phone").fetchNewRides(from: try local(server.port), secret: secret, since: nil, known: [])
        try await Task.sleep(for: .milliseconds(300))
        #expect(server.connectionEndErrors.isEmpty, "\(server.connectionEndErrors)")
    }
}
