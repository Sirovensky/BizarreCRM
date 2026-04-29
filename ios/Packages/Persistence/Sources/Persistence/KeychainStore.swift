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

    /// Generates a new random 256-bit passphrase if missing; returns existing otherwise.
    public func dbPassphrase() throws -> String {
        if let existing = get(.dbPassphrase) { return existing }
        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }.base64EncodedString()
        try set(raw, for: .dbPassphrase)
        return raw
    }

    // MARK: - §28.1 Delete on logout

    /// Keys that are scoped to a specific user / tenant and must be deleted
    /// when that user signs out or a tenant is removed.
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

    /// Removes all Keychain items that are scoped to the active user session.
    ///
    /// Call this during logout or when a tenant record is being purged.
    /// ``rememberedEmail`` is intentionally preserved across logouts so the
    /// login screen can pre-populate the email field for convenience.
    ///
    /// - Parameter tenantSlug: Unused today (single-keychain-service model),
    ///   but accepted for forward-compatibility with per-tenant service naming.
    public func deleteUserScoped(tenantSlug: String? = nil) {
        for key in Self.userScopedKeys {
            try? keychain.remove(key.rawValue)
        }
    }
}
