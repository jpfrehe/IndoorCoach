import Foundation
import Security

/// Tiny generic-password Keychain wrapper. Items are device-only and available after first unlock.
public struct Keychain: Sendable {
    public let service: String
    /// macOS only: use the data-protection keychain (no legacy "allow access" prompts when the binary changes).
    /// Needs a signed app with an application identifier; unsigned builds get errSecMissingEntitlement.
    public let dataProtection: Bool

    public init(service: String = "app.indoorcoach.secrets", dataProtection: Bool = false) {
        self.service = service
        self.dataProtection = dataProtection
    }

    public enum Key: String, Sendable {
        case claudeAPIKey = "claude.apiKey"
        case stravaClientSecret = "strava.clientSecret"
        case stravaTokens = "strava.tokens"
        case myWhooshSession = "mywhoosh.session"
        /// IndoorCoach Brücke: the long pairing secret (Mac: its own; iPhone: the paired Mac's).
        case bridgeSecret = "bridge.secret"
    }

    public func data(_ key: Key) -> Data? {
        withFallback(alsoWhenNotFound: true) { useDataProtection in
            var query = baseQuery(key, dataProtection: useDataProtection)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            return (status, status == errSecSuccess ? item as? Data : nil)
        }
    }

    public func string(_ key: Key) -> String? {
        data(key).flatMap { String(data: $0, encoding: .utf8) }
    }

    @discardableResult
    public func set(_ data: Data?, for key: Key) -> Bool {
        // A delete must also reach an item that lives in the login keychain.
        withFallback(alsoWhenNotFound: data == nil) { useDataProtection in
            let query = baseQuery(key, dataProtection: useDataProtection)
            guard let data else {
                let status = SecItemDelete(query as CFDictionary)
                return (status, status == errSecSuccess || status == errSecItemNotFound)
            }
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                var add = query
                add.merge(attributes) { $1 }
                status = SecItemAdd(add as CFDictionary, nil)
            }
            return (status, status == errSecSuccess)
        }
    }

    /// macOS: the data-protection keychain needs an application identifier (a provisioning profile). A build without
    /// one – locally signed, Developer ID without profile, the unsigned test runner – gets errSecMissingEntitlement and
    /// uses the login keychain instead. With a stable code signature that keychain does not ask again after rebuilds.
    /// Searches without the entitlement report "not found" rather than the missing entitlement, so reads and deletes
    /// also look in the login keychain then.
    private func withFallback<T>(alsoWhenNotFound: Bool = false, _ operation: (Bool) -> (OSStatus, T)) -> T {
        let first = operation(dataProtection)
        #if os(macOS)
        if dataProtection, first.0 == errSecMissingEntitlement || (alsoWhenNotFound && first.0 == errSecItemNotFound) {
            return operation(false).1
        }
        #endif
        return first.1
    }

    @discardableResult
    public func set(_ string: String?, for key: Key) -> Bool {
        let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines)
        return set((trimmed?.isEmpty ?? true) ? nil : trimmed!.data(using: .utf8), for: key)
    }

    private func baseQuery(_ key: Key, dataProtection: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrSynchronizable as String: false
        ]
        #if os(macOS)
        if dataProtection { query[kSecUseDataProtectionKeychain as String] = true }
        #endif
        return query
    }
}

/// Persists Strava tokens as JSON in the Keychain.
public struct KeychainStravaTokenStore: StravaTokenStore {
    let keychain: Keychain
    public init(keychain: Keychain = Keychain()) { self.keychain = keychain }

    public func loadTokens() -> StravaTokens? {
        guard let data = keychain.data(.stravaTokens) else { return nil }
        return try? JSONDecoder().decode(StravaTokens.self, from: data)
    }

    public func saveTokens(_ tokens: StravaTokens?) {
        keychain.set(tokens.flatMap { try? JSONEncoder().encode($0) }, for: .stravaTokens)
    }
}
