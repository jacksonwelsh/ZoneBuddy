import Foundation
import Security

/// Minimal Keychain wrapper for storing a small blob (the Strava token bundle)
/// under a string account key. Generic-password items, scoped to this app.
///
/// Secrets (OAuth tokens) belong in the Keychain rather than iCloud KV / UserDefaults
/// so they're encrypted at rest and excluded from plaintext backups.
enum KeychainStore {
    private static let service = "dev.jacksn.ZoneBuddy.strava"

    @discardableResult
    static func save(_ data: Data, account: String) -> Bool {
        // Delete any existing item first so we don't fight `errSecDuplicateItem`.
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func read(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
