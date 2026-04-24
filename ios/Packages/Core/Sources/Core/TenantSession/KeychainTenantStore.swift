import Foundation
import Security

// §79 Multi-Tenant Session management — Keychain persistence layer

/// Low-level Keychain helpers used by `TenantSessionStore`.
///
/// Extracted into its own type so it can be replaced with a fake in tests
/// without the `actor` isolation of the store getting in the way.
public protocol KeychainStoring: Sendable {
    func read(account: String) throws -> Data?
    func write(_ data: Data, account: String) throws
    func delete(account: String) throws
}

/// Production Keychain implementation (Security framework).
public struct TenantKeychainStore: KeychainStoring, Sendable {

    private let service: String

    public init(service: String = "com.bizarrecrm.tenant-sessions") {
        self.service = service
    }

    public func read(account: String) throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      account,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.readFailed(status)
        }
        return result as? Data
    }

    public func write(_ data: Data, account: String) throws {
        // Attempt update first; insert if item is not present yet.
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let attrs: [CFString: Any] = [kSecValueData: data]

        var status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw KeychainError.writeFailed(status)
        }
    }

    public func delete(account: String) throws {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

/// Errors surfaced by Keychain operations.
public enum KeychainError: Error, Equatable {
    case readFailed(OSStatus)
    case writeFailed(OSStatus)
    case deleteFailed(OSStatus)
    case decodingFailed
}
