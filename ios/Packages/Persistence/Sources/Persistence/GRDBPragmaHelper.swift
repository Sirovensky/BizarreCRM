import Foundation
import GRDB

// §29 Performance — GRDB performance-pragma helper.
//
// Centralises the SQLite PRAGMAs that influence read/write throughput so they
// are applied consistently on every connection and are easy to tune in one
// place.
//
// Pragmas applied:
//   • journal_mode = WAL       — allows concurrent readers with a single writer
//   • synchronous  = NORMAL    — durable on power-loss without full fsync on
//                                every write (WAL + NORMAL is safe per SQLite docs)
//   • cache_size   = -4096     — 4 MB page cache per connection (negative = kibibytes)
//   • temp_store   = MEMORY    — temp tables live in RAM, not a temp file
//   • mmap_size    = 134217728 — 128 MB memory-mapped I/O for read-heavy queries
//
// Usage: call `GRDBPragmaHelper.applyPerformancePragmas(to:)` inside a
// `Configuration.prepareDatabase` closure before the pool is created.

/// Applies a curated set of performance PRAGMAs to a GRDB `Database` connection.
///
/// ```swift
/// var config = Configuration()
/// config.prepareDatabase { db in
///     try db.execute(sql: "PRAGMA foreign_keys = ON")
///     try GRDBPragmaHelper.applyPerformancePragmas(to: db)
/// }
/// ```
public enum GRDBPragmaHelper {

    // MARK: - Configuration

    /// WAL journal mode — enables concurrent readers.
    public static let journalMode: String = "WAL"

    /// Page-cache size (negative = kibibytes; –4096 → 4 MB).
    public static let cacheSizeKiB: Int = -4_096

    /// Memory-mapped I/O window in bytes (128 MB).
    public static let mmapSizeBytes: Int = 128 * 1_024 * 1_024

    // MARK: - Public API

    /// Apply all performance PRAGMAs atomically to `db`.
    ///
    /// Safe to call from a `Configuration.prepareDatabase` closure because GRDB
    /// serialises those calls on each new connection.
    ///
    /// - Parameter db: The freshly opened GRDB `Database` connection.
    /// - Throws: If any PRAGMA statement fails (extremely unlikely — treated as
    ///   programmer error so this propagates rather than being swallowed).
    public static func applyPerformancePragmas(to db: GRDB.Database) throws {
        // WAL mode — applied once; subsequent connections inherit it from the
        // DB file header, but re-issuing the pragma is idempotent and cheap.
        try db.execute(sql: "PRAGMA journal_mode = WAL")

        // NORMAL synchronous is safe with WAL; FULL would add fsync overhead.
        try db.execute(sql: "PRAGMA synchronous = NORMAL")

        // Negative values mean kibibytes; 4 MB is comfortably above default (2 MB).
        try db.execute(sql: "PRAGMA cache_size = \(cacheSizeKiB)")

        // Keep temp tables in memory rather than writing a temp file.
        try db.execute(sql: "PRAGMA temp_store = MEMORY")

        // 128 MB mmap window — reduces system-call overhead for read-heavy paths.
        try db.execute(sql: "PRAGMA mmap_size = \(mmapSizeBytes)")
    }

    // MARK: - Diagnostic

    /// Returns a snapshot of current PRAGMA values for the connection.
    ///
    /// Useful in tests and Settings → Diagnostics to verify pragmas are active.
    public static func diagnosticSnapshot(from db: GRDB.Database) throws -> PragmaSnapshot {
        let journalMode = try String.fetchOne(db, sql: "PRAGMA journal_mode") ?? "unknown"
        let synchronous = try Int.fetchOne(db, sql: "PRAGMA synchronous") ?? -1
        let cacheSize   = try Int.fetchOne(db, sql: "PRAGMA cache_size") ?? 0
        let tempStore   = try Int.fetchOne(db, sql: "PRAGMA temp_store") ?? 0
        let mmapSize    = try Int.fetchOne(db, sql: "PRAGMA mmap_size") ?? 0
        return PragmaSnapshot(
            journalMode: journalMode,
            synchronous: synchronous,
            cacheSize: cacheSize,
            tempStore: tempStore,
            mmapSize: mmapSize
        )
    }

    /// Lightweight value type for PRAGMA diagnostics.
    public struct PragmaSnapshot: Sendable, Equatable {
        public let journalMode: String
        /// 0 = OFF, 1 = NORMAL, 2 = FULL, 3 = EXTRA
        public let synchronous: Int
        public let cacheSize: Int
        /// 0 = DEFAULT, 1 = FILE, 2 = MEMORY
        public let tempStore: Int
        public let mmapSize: Int

        public var isWAL: Bool { journalMode.uppercased() == "WAL" }
        public var isSynchronousNormal: Bool { synchronous == 1 }
    }
}
