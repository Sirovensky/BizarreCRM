import Foundation
import KeychainAccess
import CryptoKit
import Core

public enum KeychainKey: String, Sendable {
    case accessToken    = "auth.access_token"
    case refreshToken   = "auth.refresh_token"
    case pinHash        = "auth.pin_hash"
    case pinLength      = "auth.pin_length"
    case pinFailCount   = "auth.pin_fail_count"
    case pinLockUntil   = "auth.pin_lock_until"
    case dbPassphrase   = "db.passphrase"
    case backupCodes    = "auth.backup_codes"
    case blockChypAuth  = "hardware.blockchyp_auth"
    /// §79 Multi-tenant: ID of the last-active tenant.
    case activeTenantId  = "auth.active_tenant_id"
    /// §2 Remember-me: last-used email for login pre-fill. Never stores password.
    case rememberedEmail = "auth.remembered_email"
}

public final class KeychainStore: @unchecked Sendable {
    public static let shared = KeychainStore()

    private let keychain: Keychain

    private init() {
        self.keychain = Keychain(service: "com.bizarrecrm")
            .accessibility(.afterFirstUnlockThisDeviceOnly)
    }

    public func set(_ value: String, for key: KeychainKey) throws {
        try keychain.set(value, key: key.rawValue)
    }

    public func get(_ key: KeychainKey) -> String? {
        try? keychain.get(key.rawValue)
    }

    public func remove(_ key: KeychainKey) throws {
        try keychain.remove(key.rawValue)
    }

    public func clearAll() {
        try? keychain.removeAll()
    }

    // MARK: — §28.1 Logout cleanup

    /// Removes all user-session and tenant-scoped Keychain items on sign-out.
    ///
    /// The DB passphrase (`dbPassphrase`) is intentionally NOT cleared here —
    /// the encrypted database stays on disk until the user taps "Reset" in the
    /// Danger Zone, and the passphrase must survive a sign-out → sign-in cycle
    /// for the same tenant so the DB remains accessible.
    ///
    /// `blockChypAuth` is also preserved — hardware pairing should survive logout.
    public func deleteSessionKeys() {
        let sessionKeys: [KeychainKey] = [
            .accessToken,
            .refreshToken,
            .pinHash,
            .pinLength,
            .pinFailCount,
            .pinLockUntil,
            .backupCodes,
            .activeTenantId,
            .rememberedEmail,
        ]
        for key in sessionKeys {
            try? keychain.remove(key.rawValue)
        }
    }

    /// Full wipe: removes ALL Keychain items including the DB passphrase.
    ///
    /// Call from Settings → Danger Zone → Reset, not from routine logout.
    public func deleteAll() {
        clearAll()
    }

    /// Generates a new random 256-bit passphrase if missing; returns existing otherwise.
    ///
    /// - Note: Prefer ``tenantPassphrase(for:)`` for per-tenant DB isolation (§28.12).
    ///   This method is retained for backwards-compatibility with the single-tenant
    ///   bootstrap path and for the global fallback before a tenant is selected.
    public func dbPassphrase() throws -> String {
        if let existing = get(.dbPassphrase) { return existing }
        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }.base64EncodedString()
        try set(raw, for: .dbPassphrase)
        return raw
    }

    // MARK: — §28.12 Per-tenant DB passphrase

    /// Returns a per-tenant 256-bit DB passphrase stored under the
    /// key `"db.passphrase.<tenantSlug>"`. Generates one on first access.
    public func tenantPassphrase(for tenantSlug: String) throws -> String {
        precondition(!tenantSlug.isEmpty, "tenantSlug must be non-empty")
        let keychainKey = "db.passphrase.\(tenantSlug)"
        if let existing = try? keychain.get(keychainKey) { return existing }
        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }.base64EncodedString()
        try keychain.set(raw, key: keychainKey)
        return raw
    }

    /// Removes the per-tenant DB passphrase for `tenantSlug` from the Keychain.
    public func removeTenantPassphrase(for tenantSlug: String) throws {
        precondition(!tenantSlug.isEmpty, "tenantSlug must be non-empty")
        let keychainKey = "db.passphrase.\(tenantSlug)"
        try keychain.remove(keychainKey)
    }

    // MARK: - §28.1 Delete on logout

    /// Keys scoped to a specific user / tenant — deleted on logout / tenant purge.
    private static let userScopedKeys: [KeychainKey] = [
        .accessToken,
        .refreshToken,
        .pinHash,
        .pinLength,
        .pinFailCount,
        .pinLockUntil,
        .dbPassphrase,
        .backupCodes,
        .blockChypAuth,
        .activeTenantId,
    ]

    /// Removes all Keychain items scoped to the active user session.
    /// `rememberedEmail` is intentionally preserved.
    public func deleteUserScoped(tenantSlug: String? = nil) {
        for key in Self.userScopedKeys {
            try? keychain.remove(key.rawValue)
        }
    }
}
