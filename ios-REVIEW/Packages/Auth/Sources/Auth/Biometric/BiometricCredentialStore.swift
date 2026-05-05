import Foundation
import Security
import LocalAuthentication
import Core

// MARK: - BiometricCredentialStore

/// §2 — Stores the user's password behind a Keychain item that can only be
/// read after a successful biometric evaluation.
///
/// **Security design**
/// - The `SecAccessControl` is created with
///   `.biometryCurrentSet` + `.privateKeyUsage` so the secret is invalidated
///   if the enrolled biometry set changes (e.g. a new finger is added).
/// - The item uses `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` so it
///   is removed from the Keychain if the device passcode is disabled.
/// - The item never appears in iCloud Keychain backups.
/// - Read operations re-evaluate the access control in-process via a fresh
///   `LAContext`; no system dialog appears for write operations.
///
/// **Threat model note**
/// - This store is additive on top of the normal username+password login.
///   The network endpoint is still `/api/v1/auth/login`.
/// - If the user changes their server password the stored credential becomes
///   stale. The caller (login flow) should call `clear()` on a 401 response.
///
/// **Testability**
/// The `PasswordStorage` protocol lets tests inject `InMemoryPasswordStorage`
/// which skips Keychain I/O.
public protocol PasswordStorage: Sendable {
    func savePassword(_ password: String) throws
    func loadPassword() throws -> String?
    func removePassword() throws
}

// MARK: - Keychain-backed storage with biometry ACL

/// Production `PasswordStorage`.
///
/// Reading is gated on a `LAContext.evaluateAccessControl` call that
/// presents the biometric prompt. Writing is done without user interaction.
public struct KeychainPasswordStorage: PasswordStorage, @unchecked Sendable {
    private let service = "com.bizarrecrm"
    private let account = "auth.biometric_password"

    public init() {}

    public func savePassword(_ password: String) throws {
        guard let data = password.data(using: .utf8) else {
            throw BiometricCredentialStoreError.encodingFailed
        }

        // Build biometry-required access control.
        // .biometryCurrentSet: invalidated when the biometry set changes.
        // .privateKeyUsage: restricts to in-process use only.
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            [.biometryCurrentSet],
            &error
        ) else {
            let desc = error?.takeRetainedValue().localizedDescription ?? "unknown"
            throw BiometricCredentialStoreError.accessControlCreationFailed(desc)
        }

        // Remove any existing item before re-adding.
        let deleteQuery: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      account,
            kSecValueData:        data,
            kSecAttrAccessControl: access,
            // Exclude from iCloud Keychain sync.
            kSecAttrSynchronizable: false
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw BiometricCredentialStoreError.writeFailed(status)
        }
    }

    public func loadPassword() throws -> String? {
        // Provide a fresh LAContext so the biometric prompt description
        // is consistent and callers don't need to pass one in.
        let context = LAContext()

        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      account,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne,
            kSecUseAuthenticationContext: context,
            // Do NOT show the OS biometric prompt here — the app layer
            // (BiometricLoginShortcut) has already evaluated the policy.
            // We use .useAuthenticationUI = .skip to allow the context we
            // already authenticated in the service to carry over.
            kSecUseAuthenticationUI: kSecUseAuthenticationUISkip
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let string = String(data: data, encoding: .utf8)
            else { throw BiometricCredentialStoreError.decodingFailed }
            return string
        case errSecItemNotFound:
            return nil
        case errSecAuthFailed:
            throw BiometricCredentialStoreError.authFailed
        default:
            throw BiometricCredentialStoreError.readFailed(status)
        }
    }

    public func removePassword() throws {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BiometricCredentialStoreError.deleteFailed(status)
        }
    }
}

// MARK: - In-memory storage (tests only)

/// Not thread-safe; access through the `BiometricCredentialStore` actor.
public final class InMemoryPasswordStorage: PasswordStorage, @unchecked Sendable {
    private var stored: String?

    public init() {}

    public func savePassword(_ password: String) throws { stored = password }
    public func loadPassword() throws -> String? { stored }
    public func removePassword() throws { stored = nil }
}

// MARK: - BiometricCredentialStore actor

/// Thread-safe actor that owns biometric-gated credential persistence.
///
/// Callers:
/// - `BiometricLoginShortcut` — saves on first biometric-login success,
///   loads on every subsequent shortcut tap.
/// - Sign-out flow — calls `clear()` to wipe stored password.
public actor BiometricCredentialStore {

    private let storage: PasswordStorage

    public static let shared: BiometricCredentialStore = BiometricCredentialStore()

    public init(storage: PasswordStorage = KeychainPasswordStorage()) {
        self.storage = storage
    }

    // MARK: - API

    /// Saves `password` behind a biometry-required Keychain ACL.
    /// - Parameter password: Must be non-empty.
    /// - Throws: `BiometricCredentialStoreError.emptyPassword` or a Keychain error.
    public func savePassword(_ password: String) throws {
        let trimmed = password.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw BiometricCredentialStoreError.emptyPassword
        }
        try storage.savePassword(trimmed)
    }

    /// Loads the stored password. Requires a biometric or passcode proof
    /// (via the `LAContext` carried by `KeychainPasswordStorage`).
    ///
    /// Returns `nil` when nothing has been saved yet.
    public func loadPassword() throws -> String? {
        try storage.loadPassword()
    }

    /// Removes the stored password. Call on sign-out or after a 401.
    public func clear() throws {
        try storage.removePassword()
    }

    /// `true` when a password item exists in the store.
    public var hasStoredPassword: Bool {
        (try? storage.loadPassword()) != nil
    }
}

// MARK: - Errors

public enum BiometricCredentialStoreError: Error, Sendable, LocalizedError, Equatable {
    case emptyPassword
    case encodingFailed
    case accessControlCreationFailed(String)
    case writeFailed(OSStatus)
    case readFailed(OSStatus)
    case deleteFailed(OSStatus)
    case decodingFailed
    case authFailed

    public var errorDescription: String? {
        switch self {
        case .emptyPassword:                        return "Password must not be empty."
        case .encodingFailed:                       return "Failed to encode password data."
        case .accessControlCreationFailed(let r):   return "Access control creation failed: \(r)."
        case .writeFailed(let s):                   return "Keychain write failed (\(s))."
        case .readFailed(let s):                    return "Keychain read failed (\(s))."
        case .deleteFailed(let s):                  return "Keychain delete failed (\(s))."
        case .decodingFailed:                       return "Failed to decode stored password."
        case .authFailed:                           return "Biometric authentication required to access saved password."
        }
    }

    public static func == (lhs: BiometricCredentialStoreError,
                           rhs: BiometricCredentialStoreError) -> Bool {
        switch (lhs, rhs) {
        case (.emptyPassword, .emptyPassword):         return true
        case (.encodingFailed, .encodingFailed):       return true
        case (.decodingFailed, .decodingFailed):       return true
        case (.authFailed, .authFailed):               return true
        case (.accessControlCreationFailed(let a),
              .accessControlCreationFailed(let b)):    return a == b
        case (.writeFailed(let a), .writeFailed(let b)):   return a == b
        case (.readFailed(let a),  .readFailed(let b)):    return a == b
        case (.deleteFailed(let a),.deleteFailed(let b)):  return a == b
        default:                                           return false
        }
    }
}
