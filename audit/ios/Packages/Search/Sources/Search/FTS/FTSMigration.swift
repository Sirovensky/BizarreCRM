import Foundation
import GRDB
import Core

/// §18.3 — Registers the `006_fts5_search_index` migration programmatically.
///
/// The migration SQL is defined in
/// `Persistence/Sources/Persistence/Migrations/006_fts5_search_index.sql`
/// and is picked up automatically by `Migrator.registerFromResources()`.
/// This file documents the migration contract and provides a helper for
/// tests that open an in-memory database without the resource bundle.
public enum FTSMigration {

    /// Migration identifier — must match the SQL filename without extension.
    public static let identifier = "006_fts5_search_index"

    /// SQL that creates the FTS5 virtual table.
    /// Used by `registerInMemory(on:)` in tests.
    static let sql = """
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

    /// Register the FTS5 migration on a `DatabaseMigrator` — used by in-memory
    /// test databases that don't load resources from the bundle.
    public static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration(identifier) { db in
            try db.execute(sql: sql)
        }
    }

    /// Open an in-memory `DatabaseQueue` with the FTS5 table applied.
    /// Convenience for unit tests.
    public static func openInMemory() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        register(on: &migrator)
        try migrator.migrate(queue)
        return queue
    }
}
