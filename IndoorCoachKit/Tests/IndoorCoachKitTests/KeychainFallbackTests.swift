import Foundation
import Testing
@testable import IndoorCoachKit

#if os(macOS)
/// The Mac bridge asks for the data-protection keychain. Builds without an application identifier (unsigned test
/// runner, locally signed bridge without provisioning profile) get errSecMissingEntitlement there and must fall back
/// to the login keychain instead of losing the secret.
@Suite("Keychain fallback (macOS)", .serialized)
struct KeychainFallbackTests {
    @Test func dataProtectionFallsBackWhenTheEntitlementIsMissing() {
        let keychain = Keychain(service: "app.indoorcoach.tests.\(UUID().uuidString)", dataProtection: true)
        defer { keychain.set(nil as Data?, for: .bridgeSecret) }
        let secret = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        #expect(keychain.set(secret, for: .bridgeSecret))
        #expect(keychain.data(.bridgeSecret) == secret)
        let newer = Data(repeating: 7, count: 32)
        #expect(keychain.set(newer, for: .bridgeSecret))
        #expect(keychain.data(.bridgeSecret) == newer)
        #expect(keychain.set(nil as Data?, for: .bridgeSecret))
        #expect(keychain.data(.bridgeSecret) == nil)
    }
}
#endif
