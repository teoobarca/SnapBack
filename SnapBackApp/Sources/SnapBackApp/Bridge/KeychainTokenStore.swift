import Foundation
import Security

public enum KeychainTokenStoreError: Error {
    case osStatus(OSStatus)
    case rngFailed
}

/// Minimal wrapper around the macOS Keychain for the pair token.
/// Uses kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly so the secret does NOT
/// sync via iCloud Keychain.
public final class KeychainTokenStore {
    private let service: String
    private let account: String

    public init(service: String = "com.snapback.mobile",
                account: String = "pair-token") {
        self.service = service
        self.account = account
    }

    public func read() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    public func generateAndStore() throws -> Data {
        try delete() // idempotent

        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw KeychainTokenStoreError.rngFailed }
        let token = Data(bytes)

        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: token
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainTokenStoreError.osStatus(addStatus)
        }
        return token
    }

    public func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        throw KeychainTokenStoreError.osStatus(status)
    }
}
