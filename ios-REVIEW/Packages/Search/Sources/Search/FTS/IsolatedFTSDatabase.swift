import Foundation
import GRDB

/// §18.7 — Opens (and migrates) the Search package's own SQLite database that
/// lives under the App Group container, **isolated from the main GRDB/Persistence
/// database**.
///
/// - Location: `<AppGroup>/Library/Application Support/search_fts.sqlite`
/// - Encryption: plain SQLite (no SQLCipher) — the FTS index contains
///   display-name–level data only; PII such as phone/email is NOT stored here.
///   The OS-level file protection class `complete` handles at-rest security.
/// - Thread safety: `DatabaseQueue` serialises all reads and writes through a
///   single write queue. `FTSIndexStore` is an `actor` on top of it.
///
/// ### Schema (migration v1)
/// ```sql
/// CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(
///     entity,
///     entityId UNINDEXED,
///     title,
///     body,
///     tags,
///     updatedAt UNINDEXED,
///     tokenize = 'porter unicode61'
/// );
/// ```
///
/// Migration identifier: `"001_fts5_search_index"`
public enum IsolatedFTSDatabase {

    // MARK: - Migration ID

    public static let migrationIdentifier = "001_fts5_search_index"

    // MARK: - Schema SQL (also used by tests for in-memory databases)

    static let schemaSql = """
    CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(
        entity,
        entityId UNINDEXED,
        title,
        body,
        tags,
        updatedAt UNINDEXED,
        tokenize = 'porter unicode61'
    );
    """

    // MARK: - Open

    /// Opens the isolated FTS5 database under the App Group container.
    ///
    /// If the App Group URL cannot be resolved (e.g. during unit tests without
    /// an entitlement), falls back to the app's Documents directory so the
    /// function never throws due to an unavailable container.
    ///
    /// - Parameter appGroupIdentifier: The App Group ID.
    ///   Defaults to `"group.com.bizarrecrm"` (the production group).
    /// - Returns: A migrated `DatabaseQueue`.
    public static func open(
        appGroupIdentifier: String = "group.com.bizarrecrm"
    ) throws -> DatabaseQueue {
        let directory = resolveDirectory(appGroupIdentifier: appGroupIdentifier)
        try createDirectoryIfNeeded(at: directory)

        let dbURL = directory.appendingPathComponent("search_fts.sqlite")

        var config = Configuration()
        config.label = "com.bizarrecrm.search.fts"

        let queue = try DatabaseQueue(path: dbURL.path, configuration: config)

        // Enable file-protection on the database file.
        try? (dbURL as NSURL).setResourceValue(
            URLFileProtection.complete,
            forKey: .fileProtectionKey
        )

        try migrate(queue)
        return queue
    }

    /// Opens an in-memory `DatabaseQueue` with the FTS5 schema applied.
    /// Convenience for unit tests — no file I/O, no App Group required.
    public static func openInMemory() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try migrate(queue)
        return queue
    }

    // MARK: - Migration

    static func migrate(_ db: DatabaseWriter) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration(migrationIdentifier) { db in
            try db.execute(sql: schemaSql)
        }
        try migrator.migrate(db)
    }

    // MARK: - Helpers

    private static func resolveDirectory(appGroupIdentifier: String) -> URL {
        if let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return groupURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
        }
        // Fallback: use the app's own support directory.
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths.first ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    private static func createDirectoryIfNeeded(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
}
