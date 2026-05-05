import Foundation
import Security
import Core

// MARK: - Storage protocol (for testability)

/// Minimal key-value storage contract used by `LastUsernameStore`.
/// Production uses raw Security framework; tests inject `InMemoryUsernameStorage`.
public protocol UsernameStorage: Sendable {
    func setUsername(_ value: String) throws
    func getUsername() -> String?
    func removeUsername() throws
}

// MARK: - Keychain-backed storage

/// Production `UsernameStorage` written directly with Security framework so
/// this file stays self-contained inside the new Biometric/ subfolder.
///
/// Key: `"auth.last_username"`
/// Accessibility: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
///   — on-device only, survives reboot-unlock, excluded from iCloud backups.
///   The username never touches `UserDefaults`.
public struct KeychainUsernameStorage: UsernameStorage, Sendable {
    private let service = "com.bizarrecrm"
    private let account = "auth.last_username"

    public init() {}

    public func setUsername(_ value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw LastUsernameStoreError.emptyUsername
        }
        // Delete any pre-existing item first to avoid `errSecDuplicateItem`.
        let deleteQuery: [CFString: Any] = [
            kSecClass:   kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [CFString: Any] = [
            kSecClass:                   kSecClassGenericPassword,
            kSecAttrService:             service,
            kSecAttrAccount:             account,
            kSecValueData:               data,
            kSecAttrAccessible:          kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainUsernameStorageError.writeFailed(status)
        }
    }

    public func getUsername() -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      account,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    public func removeUsername() throws {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        // errSecItemNotFound is fine — nothing to remove.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainUsernameStorageError.deleteFailed(status)
        }
    }
}

// MARK: - Keychain I/O errors (internal; callers see LastUsernameStoreError)

private enum KeychainUsernameStorageError: Error {
    case writeFailed(OSStatus)
    case deleteFailed(OSStatus)
}

// MARK: - In-memory storage (tests only)

/// Not thread-safe on its own; designed to be accessed through the
/// `LastUsernameStore` actor so no races occur.
public final class InMemoryUsernameStorage: UsernameStorage, @unchecked Sendable {
    private var stored: String?

    public init() {}

    public func setUsername(_ value: String) throws { stored = value }
    public func getUsername() -> String? { stored }
    public func removeUsername() throws { stored = nil }
}

// MARK: - LastUsernameStore

/// §2 — Remembers the last username/email typed on the login screen so it
/// can be pre-filled on the next visit.
///
/// **Security contract**
/// - Only the username/email is persisted — never a password.
/// - Storage is the system Keychain with
///   `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. This keeps the
///   value on-device and prevents it appearing in iCloud Keychain backups
///   or plaintext `UserDefaults`.
///
/// Integration hook (wired by `BiometricLoginShortcut`):
/// ```swift
/// // On successful biometric login:
/// try await LastUsernameStore.shared.save(username: flow.username)
///
/// // On credentials panel appear:
/// if let last = await LastUsernameStore.shared.lastUsername() {
///     flow.username = last
/// }
/// ```
public actor LastUsernameStore {

    private let storage: UsernameStorage

    public static let shared: LastUsernameStore = LastUsernameStore()

    public init(storage: UsernameStorage = KeychainUsernameStorage()) {
        self.storage = storage
    }

    // MARK: - API

    /// Persist `username` in the Keychain.
    /// - Throws: `LastUsernameStoreError.emptyUsername` when `username` is blank,
    ///   or a Keychain write error.
    public func save(username: String) throws {
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw LastUsernameStoreError.emptyUsername
        }
        try storage.setUsername(trimmed)
    }

    /// Returns the last stored username, or `nil` when none has been saved.
    public func lastUsername() -> String? {
        storage.getUsername()
    }

    /// Removes the stored username. Call on sign-out or when the user
    /// disables "remember username".
    public func clear() throws {
        try storage.removeUsername()
    }
}

// MARK: - Errors

public enum LastUsernameStoreError: Error, Sendable, LocalizedError {
    case emptyUsername

    public var errorDescription: String? {
        switch self {
        case .emptyUsername: return "Cannot remember an empty username."
        }
    }
}
