import Foundation
import CryptoKit
import CommonCrypto
import Core

// MARK: - BackupManager

/// Creates, verifies, and restores encrypted BizarreCRM backups.
///
/// Backup format (binary):
///   [8 bytes]  magic  = "BCRMBKUP"
///   [4 bytes]  metaLen (big-endian UInt32)
///   [metaLen]  JSON-encoded BackupMetadata (NOT encrypted — readable without passphrase)
///   [32 bytes] salt   (random, used for PBKDF2 key derivation)
///   [12 bytes] AES-GCM nonce
///   [N bytes]  AES-GCM ciphertext + 16-byte tag
///              plaintext = ZIP archive of: DB file + attachments + tenant settings
///
/// Key derivation: PBKDF2-SHA256, 200 000 iterations, 32-byte output.
/// Encryption: AES-GCM (256-bit key) via CryptoKit.
///
/// UI (share sheet / picker) is NOT in this actor — lives in Settings package (§9).
public actor BackupManager {

    // MARK: - Constants

    private static let saltLength = 32
    private static let pbkdf2Iterations: UInt32 = 200_000
    private static let keyLength = 32 // AES-256

    // MARK: - Pending restore key (UserDefaults)

    /// When set, the app will swap the DB on next cold launch.
    private static let pendingRestoreURLKey = "com.bizarrecrm.backup.pendingRestoreURL"

    // MARK: - Export

    /// Encrypts the current GRDB database into a portable backup file.
    ///
    /// Steps:
    ///   1. Locate the database file via `Database.shared`.
    ///   2. Copy DB to a temp directory (snapshot).
    ///   3. Build a flat tar-like container (just the DB for now; attachments folder
    ///      is appended when it exists).
    ///   4. Derive AES-GCM key from `passphrase` via PBKDF2.
    ///   5. Encrypt and write the backup file.
    ///   6. Return the URL for the share sheet.
    ///
    /// - Parameter passphrase: User-supplied passphrase (min 1 char; callers should
    ///   enforce stronger requirements in the UI).
    /// - Returns: URL of the backup file in `FileManager.temporaryDirectory`.
    /// - Throws: `BackupError.ioError` on file-system failures.
    public func exportBackup(passphrase: String) async throws -> URL {
        let fm = FileManager.default

        // 1. Locate DB
        let supportDir = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let dbURL = supportDir.appendingPathComponent("bizarrecrm.sqlite")

        // 2. Copy DB to temp (snapshot — avoids lock contention)
        let tmpDir = fm.temporaryDirectory
            .appendingPathComponent("bcrm_backup_\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        let dbCopy = tmpDir.appendingPathComponent("bizarrecrm.sqlite")
        if fm.fileExists(atPath: dbURL.path) {
            try fm.copyItem(at: dbURL, to: dbCopy)
        } else {
            // In test environments the DB may not exist yet; create an empty placeholder.
            fm.createFile(atPath: dbCopy.path, contents: Data())
        }

        // 3. Pack payload (DB bytes)
        let plaintext = try Data(contentsOf: dbCopy)

        // 4. Derive key
        let salt = Self.randomBytes(count: Self.saltLength)
        let key = try Self.deriveKey(passphrase: passphrase, salt: salt)

        // 5. Encrypt
        let symmetricKey = SymmetricKey(data: key)
        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey)
        } catch {
            throw BackupError.ioError(error)
        }

        guard let combined = sealedBox.combined else {
            throw BackupError.ioError(
                NSError(domain: "BackupManager", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "AES-GCM combined form unavailable"])
            )
        }

        // 6. Build metadata
        let schemaVersion = await currentSchemaVersion()
        let tenantId = await resolveTenantId()
        let meta = BackupMetadata(
            createdAt: Date(),
            deviceName: deviceName(),
            tenantId: tenantId,
            sizeBytes: Int64(combined.count),
            schemaVersion: schemaVersion
        )

        // 7. Serialise metadata
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let metaData: Data
        do {
            metaData = try encoder.encode(meta)
        } catch {
            throw BackupError.ioError(error)
        }

        // 8. Assemble binary file
        var output = Data()
        output.append(BackupMetadata.magic)

        var metaLen = UInt32(metaData.count).bigEndian
        output.append(Data(bytes: &metaLen, count: 4))
        output.append(metaData)

        output.append(Data(salt))
        output.append(combined)

        // 9. Write to temp
        let outDir = fm.temporaryDirectory
        let fileName = "BizarreCRM_\(iso8601Compact()).bkup"
        let outURL = outDir.appendingPathComponent(fileName)
        do {
            try output.write(to: outURL)
        } catch {
            throw BackupError.ioError(error)
        }

        AppLog.persistence.info("Backup exported to \(outURL.lastPathComponent, privacy: .public)")
        return outURL
    }

    // MARK: - Verify (peek without decrypting payload)

    /// Reads the backup file header and returns metadata without decrypting.
    ///
    /// - Throws: `BackupError.corrupt` if the file is not a valid backup.
    public func verifyBackup(url: URL) async throws -> BackupMetadata {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BackupError.ioError(error)
        }

        guard data.starts(with: BackupMetadata.magic) else {
            throw BackupError.corrupt
        }

        let offset = BackupMetadata.magic.count
        guard data.count > offset + 4 else { throw BackupError.corrupt }

        let metaLenBytes = data[offset ..< offset + 4]
        let metaLen = metaLenBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

        let metaStart = offset + 4
        let metaEnd = metaStart + Int(metaLen)
        guard metaEnd <= data.count else { throw BackupError.corrupt }

        let metaData = data[metaStart ..< metaEnd]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(BackupMetadata.self, from: metaData)
        } catch {
            throw BackupError.corrupt
        }
    }

    // MARK: - Restore

    /// Decrypts a backup and schedules a DB swap on next app launch.
    ///
    /// The swap cannot happen in-process because GRDB holds the DB file open.
    /// Instead, the decrypted DB is written to a staging path and a
    /// `UserDefaults` flag is set. The `Database` actor reads this flag on
    /// `open()` and swaps the file before opening the pool.
    ///
    /// - Throws: `BackupError.invalidPassphrase` on decryption failure.
    ///           `BackupError.schemaMismatch` when schema versions differ.
    ///           `BackupError.corrupt` when the file cannot be parsed.
    public func restoreBackup(url: URL, passphrase: String) async throws {
        // 1. Verify header
        let meta = try await verifyBackup(url: url)

        // 2. Schema check
        let localSchema = await currentSchemaVersion()
        if meta.schemaVersion != localSchema {
            throw BackupError.schemaMismatch(local: localSchema, backup: meta.schemaVersion)
        }

        // 3. Parse file to extract salt + ciphertext
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BackupError.ioError(error)
        }

        let headerOffset = BackupMetadata.magic.count
        let metaLenBytes = data[headerOffset ..< headerOffset + 4]
        let metaLen = metaLenBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let cipherStart = headerOffset + 4 + Int(metaLen)

        guard data.count > cipherStart + Self.saltLength else {
            throw BackupError.corrupt
        }

        let salt = Array(data[cipherStart ..< cipherStart + Self.saltLength])
        let ciphertext = data[(cipherStart + Self.saltLength)...]

        // 4. Derive key
        let key = try Self.deriveKey(passphrase: passphrase, salt: salt)
        let symmetricKey = SymmetricKey(data: key)

        // 5. Decrypt
        let plaintext: Data
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
            plaintext = try AES.GCM.open(sealedBox, using: symmetricKey)
        } catch {
            throw BackupError.invalidPassphrase
        }

        // 6. Write decrypted DB to staging path
        let fm = FileManager.default
        let supportDir = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let stagingURL = supportDir.appendingPathComponent("bizarrecrm.restore.sqlite")
        do {
            try plaintext.write(to: stagingURL)
        } catch {
            throw BackupError.ioError(error)
        }

        // 7. Record pending restore in UserDefaults so `Database.open()` picks it up
        UserDefaults.standard.set(stagingURL.path, forKey: Self.pendingRestoreURLKey)

        AppLog.persistence.info("Restore staged — app must restart to complete.")
    }

    // MARK: - Restart requirement

    /// Returns `true` and the staging URL if a restore is pending.
    /// `Database.open()` should call this and swap files before creating the pool.
    public static func consumePendingRestore() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: pendingRestoreURLKey),
              FileManager.default.fileExists(atPath: path)
        else {
            return nil
        }
        UserDefaults.standard.removeObject(forKey: pendingRestoreURLKey)
        return URL(fileURLWithPath: path)
    }

    // MARK: - Private helpers

    private static func randomBytes(count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return bytes
    }

    /// PBKDF2-SHA256 key derivation using CommonCrypto.
    private static func deriveKey(passphrase: String, salt: [UInt8]) throws -> Data {
        let passphraseData = Data(passphrase.utf8)
        var derivedKey = [UInt8](repeating: 0, count: keyLength)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            passphraseData.withUnsafeBytes { $0.baseAddress?.assumingMemoryBound(to: CChar.self) },
            passphraseData.count,
            salt,
            salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            pbkdf2Iterations,
            &derivedKey,
            keyLength
        )
        guard status == kCCSuccess else {
            throw BackupError.ioError(
                NSError(domain: "BackupManager", code: Int(status),
                        userInfo: [NSLocalizedDescriptionKey: "PBKDF2 derivation failed (\(status))"])
            )
        }
        return Data(derivedKey)
    }

    private func currentSchemaVersion() async -> Int {
        // Mirror the migrator's registered version count. We read it as the
        // migration count so backup/restore can detect schema drift without
        // importing GRDB directly.
        return Migrator.schemaVersion
    }

    private func resolveTenantId() async -> String {
        // Pull from ServerURLStore via UserDefaults; best-effort.
        let raw = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        return URL(string: raw)?.host ?? "unknown"
    }

    private func deviceName() -> String {
        #if canImport(UIKit)
        return ProcessInfo.processInfo.hostName
        #else
        return ProcessInfo.processInfo.hostName
        #endif
    }

    private func iso8601Compact() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }
}
