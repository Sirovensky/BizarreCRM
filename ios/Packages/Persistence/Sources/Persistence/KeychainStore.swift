import Foundation
import KeychainAccess
import CryptoKit
import Core

public enum KeychainKey: String, Sendable {
    case accessToken    = "auth.access_token"
    case refreshToken   = "auth.refresh_token"
    case pinHash        = "auth.pin_hash"
    case dbPassphrase   = "db.passphrase"
    case backupCodes    = "auth.backup_codes"
    case blockChypAuth  = "hardware.blockchyp_auth"
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
}
