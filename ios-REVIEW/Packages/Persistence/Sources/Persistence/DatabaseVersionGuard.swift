import Foundation
import GRDB
import Core

// §1.6 Migration safety guards — forward-only, no downgrade
//
// The guard is called from `Database.open(at:)` BEFORE running migrations.
// It reads the GRDB migration tracking table (`grdb_migrations`) to detect
// whether the on-disk DB was created by a newer app version than the current
// binary knows about.
//
// Why we need this:
//  - A user might run a newer app version, migrate to schema N, then roll
//    back to an older binary (e.g. TestFlight undo).
//  - GRDB's DatabaseMigrator will refuse to run older migrations on top of
//    a partially-migrated DB (by design), but it won't surface a friendly
//    error — it just leaves the DB in the newer state while the older app
//    may crash or misread the schema.
//  - `DatabaseVersionGuard` detects this mismatch on startup and surfaces a
//    human-readable error that callers can present via an alert.

// MARK: - DatabaseVersionError

public enum DatabaseVersionError: Error, LocalizedError {
    /// The on-disk schema is ahead of the current app's migration set.
    /// The user must update the app or restore from a backup.
    case databaseNewerThanApp(diskVersion: Int, appVersion: Int)

    public var errorDescription: String? {
        switch self {
        case .databaseNewerThanApp(let disk, let app):
            return "Database version \(disk) is newer than this app supports (max \(app)). Update the app to continue, or contact support."
        }
    }

    public var recoverySuggestion: String? {
        return "Update BizarreCRM from the App Store. If the problem persists, contact support — do NOT delete the app (you will lose local data)."
    }
}

// MARK: - DatabaseVersionGuard

/// Stateless utility that reads the GRDB migration tracking table and
/// detects forward-only schema violations before migrations are applied.
public enum DatabaseVersionGuard {

    /// Check whether the on-disk database's applied-migration set is compatible
    /// with the current app's migration set.
    ///
    /// - Parameters:
    ///   - pool:       The GRDB pool pointing at the on-disk file.
    ///   - appVersion: The number of migrations the current binary ships. Pass
    ///                 `Migrator.schemaVersion` which counts `.sql` files in bundle.
    ///
    /// - Throws: `DatabaseVersionError.databaseNewerThanApp` if the DB has
    ///   migrations the app does not know about. Safe to call before
    ///   `DatabaseMigrator.migrate(_:)`.
    public static func checkCompatibility(pool: DatabasePool, appVersion: Int) throws {
        let appliedCount: Int = try pool.read { db in
            // GRDB creates `grdb_migrations` only after the first migration runs.
            // If the table doesn't exist yet, the DB is brand-new → compatible.
            let exists = try db.tableExists("grdb_migrations")
            guard exists else { return 0 }
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM grdb_migrations") ?? 0
        }

        if appliedCount > appVersion {
            AppLog.persistence.error(
                "DB schema ahead of app: disk=\(appliedCount, privacy: .public) app=\(appVersion, privacy: .public)"
            )
            throw DatabaseVersionError.databaseNewerThanApp(
                diskVersion: appliedCount,
                appVersion: appVersion
            )
        }

        AppLog.persistence.info(
            "DB version check: disk=\(appliedCount, privacy: .public) app=\(appVersion, privacy: .public) — OK"
        )
    }
}
