import CryptoKit
import Foundation
import Network
import Testing
@testable import IndoorCoachKit

/// Security review 18.11.2026: the 6-digit code alone must not protect the long secret (offline guessing of a
/// recorded TLS-PSK handshake), and the pairing window must not allow unlimited online guesses.
@Suite("Bridge pairing security", .serialized, .timeLimit(.minutes(1)))
struct BridgePairingSecurityTests {
    @Test func sealedSecretOpensOnlyWithTheEphemeralKeyAndTheCode() throws {
        let secret = BridgeCrypto.newPairingSecret()
        let client = Curve25519.KeyAgreement.PrivateKey()
        let blob = try BridgePairingSeal.seal(secret: secret, clientPublicKey: client.publicKey.rawRepresentation, code: "482913")
        #expect(!blob.contains(secret))                     // never on the wire in clear text (inside TLS)
        #expect(try BridgePairingSeal.open(blob, clientKey: client, code: "482913") == secret)
        #expect(throws: (any Error).self) { try BridgePairingSeal.open(blob, clientKey: client, code: "482914") }
        // A passive observer knows the code (guessed offline) and both public keys, but not a private key.
        #expect(throws: (any Error).self) {
            try BridgePairingSeal.open(blob, clientKey: Curve25519.KeyAgreement.PrivateKey(), code: "482913")
        }
    }

    @Test func pairingOverTheWireUsesTheSealedSecret() async throws {
        let secret = BridgeCrypto.newPairingSecret()
        let server = BridgeServer(name: "Mac", secret: secret, source: EmptySource(), advertise: false)
        try await server.start()
        defer { server.stop() }
        try await server.startPairing(code: "111222")
        let port = try #require(server.pairingPort)
        let bridge = DiscoveredBridge(name: "x", endpoint: .hostPort(host: "127.0.0.1", port: .init(rawValue: port)!))
        let result = try await BridgeClient(deviceName: "Phone").pair(with: bridge, code: "111222")
        #expect(result.secret == secret)
    }

    @Test func tooManyWrongCodesCloseThePairingWindow() async throws {
        let server = BridgeServer(name: "Mac", secret: BridgeCrypto.newPairingSecret(), source: EmptySource(), advertise: false)
        try await server.start()
        defer { server.stop() }
        try await server.startPairing(code: "123456")
        let port = try #require(server.pairingPort)
        let bridge = DiscoveredBridge(name: "x", endpoint: .hostPort(host: "127.0.0.1", port: .init(rawValue: port)!))
        let client = BridgeClient(deviceName: "Guesser")
        for guess in 0..<BridgeServerCore.maxPairingFailures {
            _ = try? await client.pair(with: bridge, code: String(format: "%06d", guess))
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(server.pairingPort == nil)
        await #expect(throws: (any Error).self) { _ = try await client.pair(with: bridge, code: "123456") }
    }
}

private struct EmptySource: BridgeRideSource {
    func rides(since: Date?) async -> [BridgeRide] { [] }
    func fitData(id: String) async -> Data? { nil }
}
