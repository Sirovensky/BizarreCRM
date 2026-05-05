import Foundation
import Security

/// Actor that maps base-URL strings to ``PinningPolicy`` values and persists
/// user-trusted pins (self-hosted tenants) to the Keychain.
///
/// In-memory policies (e.g. bundled cloud pins) are managed via
/// ``setPolicyInMemory(_:for:)``. Keychain-backed policies (self-hosted
/// tenants where the operator generates their own cert) are added with
/// ``persistPolicy(_:for:)`` and survive app restarts.
///
/// Callers resolve the active policy with ``policy(for:)``, which merges the
/// in-memory and persisted pin sets, with in-memory pins taking precedence on
/// failClosed/allowBackupIfPinsEmpty flags.
///
/// Ownership: §1.2 TLS Pinning (iOS)
public actor PinningStore {
    // MARK: - Types

    /// Errors thrown by Keychain operations.
    public enum KeychainError: Error, Equatable {
        case saveFailure(OSStatus)
        case deleteFailure(OSStatus)
        case encodingFailure
    }

    // MARK: - Storage

    /// In-memory policies keyed by canonicalised base URL string.
    private var inMemory: [String: PinningPolicy] = [:]

    /// Keychain service identifier for persisted pins.
    private let keychainService: String

    // MARK: - Init

    /// - Parameter keychainService: Keychain service string. Override in tests.
    public init(keychainService: String = "com.bizarrecrm.pinning") {
        self.keychainService = keychainService
    }

    // MARK: - In-memory API

    /// Stores a policy in memory only. Replaces any existing in-memory entry
    /// for the same base URL. Does NOT touch the Keychain.
    public func setPolicyInMemory(_ policy: PinningPolicy, for baseURL: URL) {
        inMemory[Self.key(for: baseURL)] = policy
    }

    /// Removes an in-memory policy without affecting Keychain-persisted pins.
    public func removePolicyInMemory(for baseURL: URL) {
        inMemory.removeValue(forKey: Self.key(for: baseURL))
    }

    // MARK: - Keychain API

    /// Persists the policy's pins to the Keychain under the given base URL.
    ///
    /// On success the pins are also stored in the in-memory cache so that
    /// subsequent ``policy(for:)`` calls do not require a Keychain round-trip.
    ///
    /// - Throws: ``KeychainError/saveFailure(_:)`` on Keychain write error.
    public func persistPolicy(_ policy: PinningPolicy, for baseURL: URL) throws {
        let k = Self.key(for: baseURL)
        let payload = try Self.encode(policy: policy)

        // Delete old entry first (SecItemUpdate is more verbose; delete+add
        // is idempotent and simpler).
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: k
        ]
        SecItemDelete(deleteQuery as CFDictionary) // Ignore "not found" status.

        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: k,
            kSecValueData: payload,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailure(status)
        }
        // Mirror to in-memory cache.
        inMemory[k] = policy
    }

    /// Removes persisted Keychain pins for the given base URL. Does not affect
    /// any in-memory policy set independently.
    ///
    /// - Throws: ``KeychainError/deleteFailure(_:)`` on unexpected Keychain error.
    public func removePersistedPolicy(for baseURL: URL) throws {
        let k = Self.key(for: baseURL)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: k
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailure(status)
        }
    }

    // MARK: - Policy Resolution

    /// Returns the effective ``PinningPolicy`` for the given base URL.
    ///
    /// Resolution order:
    /// 1. In-memory policy (set via ``setPolicyInMemory(_:for:)``) — wins on
    ///    behavioural flags (failClosed / allowBackupIfPinsEmpty).
    /// 2. Persisted Keychain policy (loaded lazily).
    /// 3. Merged: in-memory pins ∪ Keychain pins, with in-memory flags.
    /// 4. If neither exists, returns ``PinningPolicy/noPinning``.
    public func policy(for baseURL: URL) -> PinningPolicy {
        let k = Self.key(for: baseURL)
        let mem = inMemory[k]

        // Try Keychain for additional / override pins.
        let persisted = loadFromKeychain(key: k)

        switch (mem, persisted) {
        case (nil, nil):
            return .noPinning
        case (let p?, nil):
            return p
        case (nil, let p?):
            return p
        case (let m?, let p?):
            // Merge: union of pins, flags from in-memory (considered authoritative).
            let merged = m.pins.union(p.pins)
            return PinningPolicy(
                pins: merged,
                allowBackupIfPinsEmpty: m.allowBackupIfPinsEmpty,
                failClosed: m.failClosed
            )
        }
    }

    // MARK: - Private helpers

    private static func key(for url: URL) -> String {
        // Strip trailing slash and lowercase for stable comparison.
        var s = url.absoluteString
        while s.hasSuffix("/") { s.removeLast() }
        return s.lowercased()
    }

    /// Loads a ``PinningPolicy`` from the Keychain without throwing. Returns
    /// `nil` if the item is absent or cannot be decoded.
    private func loadFromKeychain(key: String) -> PinningPolicy? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return try? Self.decode(data: data)
    }

    // MARK: - Serialisation (JSON over Data arrays)

    private struct PolicyPayload: Codable {
        let pins: [Data]
        let allowBackupIfPinsEmpty: Bool
        let failClosed: Bool
    }

    private static func encode(policy: PinningPolicy) throws -> Data {
        let payload = PolicyPayload(
            pins: Array(policy.pins),
            allowBackupIfPinsEmpty: policy.allowBackupIfPinsEmpty,
            failClosed: policy.failClosed
        )
        do {
            return try JSONEncoder().encode(payload)
        } catch {
            throw KeychainError.encodingFailure
        }
    }

    private static func decode(data: Data) throws -> PinningPolicy {
        let payload = try JSONDecoder().decode(PolicyPayload.self, from: data)
        return PinningPolicy(
            pins: Set(payload.pins),
            allowBackupIfPinsEmpty: payload.allowBackupIfPinsEmpty,
            failClosed: payload.failClosed
        )
    }
}
