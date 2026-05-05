import Foundation
import Persistence
import Core

// MARK: - Storage protocol (for testability)

/// Minimal key-value storage contract used by `CredentialStore`.
/// The production implementation wraps `KeychainStore`; tests inject
/// `InMemoryEmailStorage` to avoid real Keychain writes.
public protocol EmailStorage: Sendable {
    func setEmail(_ value: String) throws
    func getEmail() -> String?
    func removeEmail() throws
}

// MARK: - Keychain-backed storage

/// Production `EmailStorage` backed by `KeychainStore`.
public struct KeychainEmailStorage: EmailStorage, Sendable {
    private let store: KeychainStore

    public init(store: KeychainStore = .shared) {
        self.store = store
    }

    public func setEmail(_ value: String) throws {
        try store.set(value, for: .rememberedEmail)
    }

    public func getEmail() -> String? {
        store.get(.rememberedEmail)
    }

    public func removeEmail() throws {
        try store.remove(.rememberedEmail)
    }
}

// MARK: - In-memory storage (tests only)

/// Not thread-safe on its own; designed to be accessed through the
/// `CredentialStore` actor so no races occur.
public final class InMemoryEmailStorage: EmailStorage, @unchecked Sendable {
    private var stored: String? = nil

    public init() {}

    public func setEmail(_ value: String) throws { stored = value }
    public func getEmail() -> String? { stored }
    public func removeEmail() throws { stored = nil }
}

// MARK: - CredentialStore

/// §2 Remember-me — stores the last-used email so it can pre-fill the
/// login form on the next visit.
///
/// **Security contract:** Only the email address is persisted. Passwords
/// are never stored here. The Keychain is the single storage backend
/// (not UserDefaults), using `afterFirstUnlockThisDeviceOnly` accessibility.
///
/// Integration hook (caller wires in `LoginFlowView`):
/// ```swift
/// // On successful login:
/// if rememberMe { try await credentialStore.rememberEmail(flow.username) }
///
/// // On view appear:
/// flow.username = await credentialStore.lastEmail() ?? ""
///
/// // Toggle handler:
/// Toggle("Remember email on this device", isOn: $rememberMe)
/// ```
public actor CredentialStore {

    private let storage: EmailStorage

    /// Shared instance backed by the real Keychain.
    public static let shared: CredentialStore = CredentialStore()

    public init(storage: EmailStorage = KeychainEmailStorage()) {
        self.storage = storage
    }

    // MARK: - Public API

    /// Persist `email` in the Keychain for the next login pre-fill.
    /// - Parameter email: The email address to remember. Must be non-empty.
    /// - Throws: `CredentialStoreError.emptyEmail` or a Keychain write error.
    public func rememberEmail(_ email: String) throws {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw CredentialStoreError.emptyEmail
        }
        try storage.setEmail(trimmed)
    }

    /// Returns the last stored email, or `nil` if none has been saved or the
    /// user called `forget()`.
    public func lastEmail() -> String? {
        storage.getEmail()
    }

    /// Clears the stored email from Keychain.
    public func forget() throws {
        try storage.removeEmail()
    }
}

// MARK: - Errors

public enum CredentialStoreError: Error, Sendable, LocalizedError {
    case emptyEmail

    public var errorDescription: String? {
        switch self {
        case .emptyEmail: return "Cannot remember an empty email address."
        }
    }
}
