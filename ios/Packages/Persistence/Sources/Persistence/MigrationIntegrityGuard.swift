import Foundation
import GRDB
import Core

// §1.6 Migration-tracking guard.
//
// GRDB's `DatabaseMigrator` records applied migration names in the internal
// `grdb_migrations` table. This guard reads that table after `migrate(pool)`
// and cross-checks it against the SQL files bundled in the app.
//
// Goal: app refuses to open the database (and surfaces an upgrade-required
// alert) if any known migration is missing — i.e., the DB was opened by a
// version of the app that had fewer migrations than the current build.
//
// This is the INVERSE of DatabaseVersionGuard.checkCompatibility (§1.6),
// which blocks when the DB is NEWER than the app. MigrationIntegrityGuard
// blocks when the DB is MISSING an expected migration (schema is incomplete).
//
// Typically this catches bugs in the migration-apply path (e.g., a SQL
// migration file was added but its registration was skipped) during CI,
// not in production — where `DatabaseMigrator.migrate` would have failed
// loudly already. The guard is a belt-and-suspenders safety net.

/// Errors thrown by ``MigrationIntegrityGuard``.
public enum MigrationIntegrityError: LocalizedError, Equatable {
    /// One or more expected migration identifiers were not found in `grdb_migrations`.
    case missingMigrations([String])

    public var errorDescription: String? {
        switch self {
        case .missingMigrations(let names):
            let list = names.joined(separator: ", ")
            return "Database is missing migrations: \(list). The app cannot open this database safely. Please reinstall or contact support."
        }
    }
}

/// §1.6 Cross-checks applied migrations vs. bundle SQL files.
///
/// Call `MigrationIntegrityGuard.verify(pool:bundle:)` immediately after
/// `Migrator.register(on:)` in `Database.open(at:)`.
public enum MigrationIntegrityGuard: Sendable {

    // MARK: — Public API

    /// Reads the list of expected migration names from SQL files in `bundle`
    /// (the `Migrations/` resource folder) and verifies each name appears in
    /// the `grdb_migrations` table.
    ///
    /// - Parameters:
    ///   - pool: The open `DatabasePool` after migrations have been applied.
    ///   - bundle: The bundle containing the `Migrations/` resource folder.
    ///             Defaults to `Bundle.module`.
    ///
    /// - Throws: ``MigrationIntegrityError.missingMigrations`` when one or
    ///   more expected names are absent from `grdb_migrations`.
    public static func verify(pool: DatabasePool, bundle: Bundle = .module) throws {
        // 1. Collect expected migration identifiers from SQL filenames.
        let expected = expectedMigrationNames(in: bundle)
        guard !expected.isEmpty else {
            // If we can't find the resource folder, assume the build is incomplete
            // (e.g., unit test with a minimal target). Log and return cleanly.
            AppLog.persistence.warning("MigrationIntegrityGuard: no SQL files found in bundle; skipping check.")
            return
        }

        // 2. Read applied migration names from GRDB's internal tracking table.
        let applied: Set<String> = try pool.read { db in
            // GRDB stores applied migration names in `grdb_migrations`.
            // The table is always present after at least one migration runs.
            guard try db.tableExists("grdb_migrations") else { return [] }
            let rows = try Row.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations")
            return Set(rows.compactMap { $0["identifier"] as String? })
        }

        // 3. Find expected names not present in applied set.
        let missing = expected.filter { !applied.contains($0) }
        guard missing.isEmpty else {
            AppLog.persistence.fault("MigrationIntegrityGuard: missing migrations: \(missing.joined(separator: ", "), privacy: .public)")
            throw MigrationIntegrityError.missingMigrations(Array(missing).sorted())
        }

        AppLog.persistence.info("MigrationIntegrityGuard: all \(expected.count) migrations verified.")
    }

    // MARK: — Internals

    /// Returns the expected migration identifiers from SQL filenames in `bundle`.
    ///
    /// Each `.sql` file in `Migrations/` maps to a migration identifier equal
    /// to its filename without the `.sql` extension (e.g., `001_initial.sql`
    /// → `"001_initial"`). This matches how `Migrator.registerFromResources`
    /// registers them with GRDB.
    static func expectedMigrationNames(in bundle: Bundle) -> [String] {
        guard let folderURL = bundle.url(forResource: "Migrations", withExtension: nil) else {
            return []
        }
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "sql" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }
}
