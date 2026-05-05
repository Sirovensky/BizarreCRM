import Foundation

// MARK: - BackupMetadata

/// Lightweight header baked into every BizarreCRM backup.
/// Stored as JSON in the first few kilobytes of the archive so
/// `BackupManager.verifyBackup(url:)` can inspect it without
/// decrypting the payload.
public struct BackupMetadata: Codable, Sendable, Hashable {
    /// Backup format version (not the DB schema version).
    public let version: Int
    /// Wall-clock time the backup was created.
    public let createdAt: Date
    /// `UIDevice.current.name` — informational only.
    public let deviceName: String
    /// Tenant identifier from the app's server URL host component.
    public let tenantId: String
    /// Compressed+encrypted payload size in bytes.
    public let sizeBytes: Int64
    /// GRDB migration version number; used for `schemaMismatch` detection.
    public let schemaVersion: Int

    /// Magic prefix written as the first 8 bytes of every backup file so
    /// `verifyBackup` can reject non-backup files immediately.
    public static let magic: Data = "BCRMBKUP".data(using: .utf8)!
    /// Current backup format version written by this build.
    public static let currentVersion: Int = 1

    public init(
        version: Int = BackupMetadata.currentVersion,
        createdAt: Date = Date(),
        deviceName: String,
        tenantId: String,
        sizeBytes: Int64 = 0,
        schemaVersion: Int
    ) {
        self.version = version
        self.createdAt = createdAt
        self.deviceName = deviceName
        self.tenantId = tenantId
        self.sizeBytes = sizeBytes
        self.schemaVersion = schemaVersion
    }
}
