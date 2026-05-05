import Foundation
import Core

// MARK: - §1.6 Backup-before-migrate
//
// Copies the SQLCipher DB file to `~/Library/Caches/` with a dated name
// before running migrations. Keeps the last 7 snapshots; older ones are
// pruned on next successful launch.
//
// The backup does NOT include the passphrase — it is encrypted-at-rest but
// can only be opened with the Keychain-stored key on the same device.
//
// Called from `Database.open(at:)` before `Migrator.register(on:)`.

public enum MigrationBackupService {

    // MARK: - Constants

    private static let maxBackupAge: TimeInterval = 7 * 24 * 60 * 60  // 7 days
    private static let backupPrefix = "pre-migration-"
    private static let backupExtension = "db"

    // MARK: - Public API

    /// Create a timestamped backup of the DB file at `sourceURL`.
    ///
    /// - Parameter sourceURL: Path of the live SQLite/SQLCipher DB file.
    /// - Returns: The URL of the written backup, or `nil` if the source does
    ///   not exist yet (first launch — no backup needed).
    @discardableResult
    public static func backup(sourceURL: URL) throws -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.path) else {
            AppLog.persistence.info("Skipping migration backup — DB not yet present.")
            return nil
        }

        let cachesDir = try fm.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let dateTag = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let fileName = "\(backupPrefix)\(dateTag).\(backupExtension)"
        let destURL  = cachesDir.appendingPathComponent(fileName)

        try fm.copyItem(at: sourceURL, to: destURL)
        AppLog.persistence.info("Migration backup written: \(fileName, privacy: .public)")

        // Prune backups older than 7 days.
        pruneOldBackups(in: cachesDir)

        return destURL
    }

    // MARK: - Pruning

    /// Remove backup snapshots older than `maxBackupAge` from `directory`.
    public static func pruneOldBackups(in directory: URL) {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-maxBackupAge)

        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return }

        let backups = contents.filter {
            $0.lastPathComponent.hasPrefix(backupPrefix) &&
            $0.pathExtension == backupExtension
        }

        for url in backups {
            let creation = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            guard let date = creation, date < cutoff else { continue }
            do {
                try fm.removeItem(at: url)
                AppLog.persistence.info("Pruned old migration backup: \(url.lastPathComponent, privacy: .public)")
            } catch {
                AppLog.persistence.warning("Could not prune migration backup: \(url.lastPathComponent, privacy: .public)")
            }
        }
    }

    // MARK: - List backups

    /// Returns all migration backup URLs sorted newest-first.
    public static func listBackups() throws -> [URL] {
        let fm = FileManager.default
        let cachesDir = try fm.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )

        let contents = try fm.contentsOfDirectory(
            at: cachesDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )

        return contents
            .filter { $0.lastPathComponent.hasPrefix(backupPrefix) && $0.pathExtension == backupExtension }
            .sorted { lhs, rhs in
                let lDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                let rDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return lDate > rDate
            }
    }
}
