import Foundation
import Observation
import Security

struct CycloneCredential: Codable, Equatable {
    let serverURL: URL
    let token: String
    let deviceID: UUID
}

@Observable
final class CycloneCredentialStore {
    static let shared = CycloneCredentialStore()

    private static let service = "dev.jacksn.ZoneBuddy.cyclone"
    private static let account = "device-credential"
    private(set) var credential: CycloneCredential?

    var isConnected: Bool { credential != nil }

    init(loadFromKeychain: Bool = true, credential: CycloneCredential? = nil) {
        if let credential {
            self.credential = credential
            return
        }
        guard loadFromKeychain, let data = Self.read(),
              let credential = try? JSONDecoder().decode(CycloneCredential.self, from: data) else { return }
        self.credential = credential
    }

    func store(_ credential: CycloneCredential) {
        self.credential = credential
        guard let data = try? JSONEncoder().encode(credential) else { return }
        Self.delete()
        SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ] as CFDictionary, nil)
    }

    func clear() {
        credential = nil
        Self.delete()
    }

    private static func read() -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        return status == errSecSuccess ? result as? Data : nil
    }

    private static func delete() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}
