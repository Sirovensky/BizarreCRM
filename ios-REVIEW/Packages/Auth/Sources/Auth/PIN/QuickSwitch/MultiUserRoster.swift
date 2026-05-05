import Foundation
import CryptoKit
import Security

// MARK: - RosterEntry

/// A single account known to this device, stored in the Keychain roster.
public struct RosterEntry: Codable, Sendable, Identifiable, Equatable {
    /// Server-assigned user ID.
    public let id: Int
    public let username: String
    public let displayName: String
    public let email: String
    public let role: String
    public let avatarUrl: String?

    /// Random per-user salt (base64-encoded, 16 bytes).
    public let pinSalt: String
    /// SHA-256 of (salt + pin), hex-encoded.
    public let pinHash: String

    public static func == (lhs: RosterEntry, rhs: RosterEntry) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - RosterStorage protocol (testability seam)

/// Minimal key-value contract for the roster storage backend.
/// Production uses `KeychainRosterStorage`; tests inject `InMemoryRosterStorage`.
public protocol RosterStorage: Sendable {
    func loadRoster() -> [RosterEntry]
    func saveRoster(_ entries: [RosterEntry]) throws
}

// MARK: - Keychain-backed storage

/// Stores the encoded roster as a single Keychain generic-password item.
/// Uses `afterFirstUnlockThisDeviceOnly` and no iCloud sync,
/// consistent with the rest of `KeychainStore` in the Persistence package.
public struct KeychainRosterStorage: RosterStorage, Sendable {
    private static let service = "com.bizarrecrm"
    private static let account = "auth.multi_user_roster"

    public init() {}

    public func loadRoster() -> [RosterEntry] {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: Self.account,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return [] }
        return (try? JSONDecoder().decode([RosterEntry].self, from: data)) ?? []
    }

    public func saveRoster(_ entries: [RosterEntry]) throws {
        let data = try JSONEncoder().encode(entries)

        // Delete any existing item first, then add fresh.
        let deleteQuery: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: Self.account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrService:        Self.service,
            kSecAttrAccount:        Self.account,
            kSecValueData:          data,
            kSecAttrAccessible:     kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable: false
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw RosterError.keychainWriteFailed(status)
        }
    }
}

// MARK: - In-memory storage (tests)

public final class InMemoryRosterStorage: RosterStorage, @unchecked Sendable {
    private var entries: [RosterEntry] = []

    public init(initial: [RosterEntry] = []) {
        self.entries = initial
    }

    public func loadRoster() -> [RosterEntry] { entries }

    public func saveRoster(_ entries: [RosterEntry]) throws {
        self.entries = entries
    }
}

// MARK: - PIN hashing helpers

public enum PINHasher {
    /// Generates a cryptographically random 16-byte salt, base64-encoded.
    public static func generateSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    /// SHA-256 of (salt + pin), returned as lowercase hex.
    ///
    /// Each user gets a unique 128-bit random salt, so even two users with
    /// the same PIN produce different hashes. SHA-256 over a random salt is
    /// sufficient for a 4-6 digit local PIN protected behind Keychain
    /// `afterFirstUnlockThisDeviceOnly`.
    public static func hash(pin: String, salt: String) -> String {
        let input = salt + pin
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Returns `true` if `pin` matches the stored hash in `entry`.
    public static func verify(pin: String, entry: RosterEntry) -> Bool {
        hash(pin: pin, salt: entry.pinSalt) == entry.pinHash
    }
}

// MARK: - MultiUserRoster actor

/// Keychain-backed roster of known accounts with their hashed PINs.
///
/// All mutations are atomic within the actor and persist to the Keychain
/// immediately. The in-memory list is the single source of truth between
/// Keychain reads (loaded once on init, kept in sync via every save).
public actor MultiUserRoster {

    // MARK: - Shared instance

    public static let shared = MultiUserRoster()

    // MARK: - State

    private var entries: [RosterEntry]
    private let storage: RosterStorage

    // MARK: - Init

    public init(storage: RosterStorage = KeychainRosterStorage()) {
        self.storage = storage
        self.entries = storage.loadRoster()
    }

    // MARK: - Public API

    /// All accounts currently in the roster, sorted by display name.
    public var all: [RosterEntry] {
        entries.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }

    /// Adds or replaces an account entry with a freshly hashed PIN.
    /// - Parameters:
    ///   - user: The server-matched user from a successful `/auth/switch-user` call.
    ///   - pin:  Raw 4-6 digit PIN to hash and store.
    public func upsert(user: SwitchedUser, pin: String) throws {
        let salt = PINHasher.generateSalt()
        let hash = PINHasher.hash(pin: pin, salt: salt)
        let entry = RosterEntry(
            id: user.id,
            username: user.username,
            displayName: user.displayName,
            email: user.email,
            role: user.role,
            avatarUrl: user.avatarUrl,
            pinSalt: salt,
            pinHash: hash
        )
        var updated = entries.filter { $0.id != user.id }
        updated.append(entry)
        try persist(updated)
    }

    /// Removes the entry for `userId`.
    public func remove(userId: Int) throws {
        let updated = entries.filter { $0.id != userId }
        try persist(updated)
    }

    /// Returns the first roster entry whose PIN hash matches `pin`, or `nil`.
    public func match(pin: String) -> RosterEntry? {
        entries.first { PINHasher.verify(pin: pin, entry: $0) }
    }

    /// Clears the entire roster (e.g. on device wipe or full sign-out).
    public func clear() throws {
        try persist([])
    }

    // MARK: - Private

    private func persist(_ updated: [RosterEntry]) throws {
        try storage.saveRoster(updated)
        entries = updated
    }
}

// MARK: - Errors

public enum RosterError: Error, LocalizedError, Sendable {
    case keychainWriteFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .keychainWriteFailed(let s):
            return "Keychain write failed for roster (\(s))."
        }
    }
}
