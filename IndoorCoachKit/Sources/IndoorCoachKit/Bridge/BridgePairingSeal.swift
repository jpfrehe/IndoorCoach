import CryptoKit
import Foundation

/// Protects the long secret during pairing beyond the 6-digit code (security review 18.11.2026).
///
/// TLS-PSK with a key derived from 6 digits can be brute-forced offline from one recorded handshake. Inside that
/// channel the phone therefore sends an ephemeral X25519 public key; the Mac answers with its own ephemeral key and
/// the secret sealed (ChaChaPoly) under HKDF(shared secret, salt: code). A passive observer who later guesses the
/// code sees both public keys but cannot derive the shared secret. An active attacker still needs the code within the
/// pairing window, where the number of attempts is limited.
enum BridgePairingSeal {
    static let info = Data("IndoorCoach-Bridge-pairing-secret-v2".utf8)

    /// Server side: `serverPublicKey (32 bytes) || ChaChaPoly box`.
    static func seal(secret: Data, clientPublicKey: Data, code: String) throws -> Data {
        let server = Curve25519.KeyAgreement.PrivateKey()
        let client = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: clientPublicKey)
        let key = try sharedKey(server.sharedSecretFromKeyAgreement(with: client), code: code)
        let box = try ChaChaPoly.seal(secret, using: key)
        return server.publicKey.rawRepresentation + box.combined
    }

    /// Client side.
    static func open(_ blob: Data, clientKey: Curve25519.KeyAgreement.PrivateKey, code: String) throws -> Data {
        guard blob.count > 32 else { throw BridgeError.malformedMessage }
        let serverKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: blob.prefix(32))
        let key = try sharedKey(clientKey.sharedSecretFromKeyAgreement(with: serverKey), code: code)
        return try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: blob.dropFirst(32)), using: key)
    }

    private static func sharedKey(_ shared: SharedSecret, code: String) -> SymmetricKey {
        shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(code.utf8), sharedInfo: info, outputByteCount: 32)
    }
}
