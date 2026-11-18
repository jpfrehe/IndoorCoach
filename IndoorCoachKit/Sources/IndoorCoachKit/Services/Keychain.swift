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
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    public func string(_ key: Key) -> String? {
        data(key).flatMap { String(data: $0, encoding: .utf8) }
    }

    @discardableResult
    public func set(_ data: Data?, for key: Key) -> Bool {
        let query = baseQuery(key)
        guard let data else {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add.merge(attributes) { $1 }
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    @discardableResult
    public func set(_ string: String?, for key: Key) -> Bool {
        let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines)
        return set((trimmed?.isEmpty ?? true) ? nil : trimmed!.data(using: .utf8), for: key)
    }

    private func baseQuery(_ key: Key) -> [String: Any] {
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
