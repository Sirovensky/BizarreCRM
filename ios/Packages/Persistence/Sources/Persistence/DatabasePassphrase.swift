import Foundation
import Security
import Core

/// §1.3 SQLCipher encryption passphrase generator + Keychain cache.
///
/// On first call, generates a cryptographically-random 32-byte (256-bit)
/// passphrase via `SecRandomCopyBytes`, hex-encodes it (64 lowercase chars),
/// and persists it to the Keychain under ``KeychainKey/dbPassphrase``.
/// Subsequent calls return the cached value.
///
/// The Keychain item is stored with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
/// (set globally on `KeychainStore.shared`'s underlying `Keychain` service),
/// which means:
///   - The passphrase is decryptable only after the device has been unlocked
///     at least once since boot (survives lock-screen, not cold-boot).
///   - It does NOT leave the device via iCloud Keychain backup.
///
/// Hex encoding lets SQLCipher consume the value directly via the
/// `PRAGMA key = "x'<hex>'"` form — no escaping concerns vs. arbitrary
/// base64/UTF-8 bytes in a SQL string literal.
public enum DatabasePassphrase {

    /// Length of the raw random key, in bytes. 32 bytes = 256 bits, the
    /// SQLCipher recommended key size.
    public static let rawByteCount = 32

    /// Length of the hex-encoded passphrase. Always `rawByteCount * 2`.
    public static let hexCharCount = rawByteCount * 2

    /// Returns the persistent 32-byte random passphrase used to encrypt
    /// the SQLCipher database. Generates + stores on first call. Subsequent
    /// calls return the cached Keychain value.
    ///
    /// - Throws: `DatabasePassphraseError.randomGenerationFailed` if
    ///   `SecRandomCopyBytes` fails (extremely rare). Re-throws Keychain
    ///   write errors.
    public static func loadOrCreate() throws -> String {
        // Cached path: an existing 64-hex-char value is what we want.
        if let existing = KeychainStore.shared.get(.dbPassphrase),
           isHexPassphrase(existing) {
            return existing
        }

        // Legacy path: an older build wrote a base64-encoded 256-bit value
        // under the same Keychain key (see `KeychainStore.dbPassphrase()`).
        // For this fresh dev-only setup we simply replace it — the on-disk
        // DB is currently NOT encrypted (SQLCipher isn't linked yet), so
        // overwriting the Keychain value is non-destructive. When SQLCipher
        // lands, the first encrypted DB will be created with the new key.
        if let legacy = KeychainStore.shared.get(.dbPassphrase) {
            AppLog.persistence.warning(
                "DatabasePassphrase: replacing legacy non-hex Keychain value (len=\(legacy.count, privacy: .public)) with new 256-bit random key"
            )
        }

        let hex = try generateHexPassphrase()
        try KeychainStore.shared.set(hex, for: .dbPassphrase)
        AppLog.persistence.info("DatabasePassphrase: generated new 256-bit DB passphrase")
        return hex
    }

    // MARK: - Internals

    /// Cryptographically-random 32-byte value, hex-encoded.
    static func generateHexPassphrase() throws -> String {
        var bytes = [UInt8](repeating: 0, count: rawByteCount)
        let status = bytes.withUnsafeMutableBufferPointer { buf in
            SecRandomCopyBytes(kSecRandomDefault, buf.count, buf.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw DatabasePassphraseError.randomGenerationFailed(status: status)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// True if `s` looks like a valid hex passphrase produced by
    /// ``generateHexPassphrase()`` — exactly `hexCharCount` characters,
    /// every character is a lowercase hex digit.
    static func isHexPassphrase(_ s: String) -> Bool {
        guard s.count == hexCharCount else { return false }
        return s.allSatisfy { c in
            (c >= "0" && c <= "9") || (c >= "a" && c <= "f")
        }
    }
}

public enum DatabasePassphraseError: Error, Equatable {
    /// `SecRandomCopyBytes` returned a non-`errSecSuccess` status.
    case randomGenerationFailed(status: OSStatus)
}
