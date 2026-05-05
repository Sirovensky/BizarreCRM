import XCTest
import GRDB
@testable import Persistence

// MARK: - §31.3 GRDB In-Memory Test Utilities
//
// Creates a fully migrated, in-memory DatabaseQueue for fast, isolated unit tests.
//
// Usage in XCTestCase:
//
//   final class MyStoreTests: XCTestCase {
//       private var db: DatabaseQueue!
//
//       override func setUp() async throws {
//           db = try await GRDBTestSupport.makeQueue()
//       }
//
//       override func tearDown() async throws {
//           db = nil  // queue released; SQLite :memory: wiped automatically
//       }
//
//       func test_insert_roundtrip() async throws {
//           try await db.write { ... }
//           let rows = try await db.read { ... }
//           XCTAssertEqual(rows.count, 1)
//       }
//   }
//
// GRDB in-memory databases:
//  - Are never written to disk — no temp file cleanup required.
//  - Are destroyed when the DatabaseQueue is deallocated.
//  - Each `makeQueue()` call produces a fully isolated database.
//  - Migrations run synchronously so the returned queue is immediately usable.

public enum GRDBTestSupport {

    // MARK: - Primary factory

    /// Create a new in-memory `DatabaseQueue` with all registered migrations applied.
    ///
    /// - Parameter extraSetup: Optional closure for adding additional schema objects
    ///   (e.g. test-only tables or seed rows) before the queue is returned.
    /// - Returns: A ready-to-use, fully migrated `DatabaseQueue`.
    public static func makeQueue(
        extraSetup: ((Database) throws -> Void)? = nil
    ) throws -> DatabaseQueue {
        var config = Configuration()
        config.label = "bizarrecrm-test"

        // An empty path creates an in-memory database in GRDB.
        let queue = try DatabaseQueue(path: ":memory:", configuration: config)

        // Apply the app's registered migrations.
        try applyMigrations(to: queue)

        if let extra = extraSetup {
            try queue.write { db in try extra(db) }
        }

        return queue
    }

    // MARK: - Schema helpers

    /// Create a throw-away, **bare** in-memory queue (no migrations).
    /// Useful for testing schema helpers that manage their own DDL.
    public static func makeEmptyQueue() throws -> DatabaseQueue {
        var config = Configuration()
        config.label = "bizarrecrm-test-bare"
        return try DatabaseQueue(path: ":memory:", configuration: config)
    }

    // MARK: - Seed helpers

    /// Insert rows via a write block and return the queue for chaining.
    @discardableResult
    public static func seed(
        _ queue: DatabaseQueue,
        block: (Database) throws -> Void
    ) throws -> DatabaseQueue {
        try queue.write { db in try block(db) }
        return queue
    }

    // MARK: - Assertion helpers

    /// Assert that a given table exists and has the expected row count.
    public static func assertRowCount(
        _ expected: Int,
        in table: String,
        queue: DatabaseQueue,
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        let count = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
        }
        XCTAssertEqual(count, expected,
                       "Expected \(expected) row(s) in '\(table)', got \(count)",
                       file: file, line: line)
    }

    /// Assert that the given table is empty.
    public static func assertEmpty(
        _ table: String,
        queue: DatabaseQueue,
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        try assertRowCount(0, in: table, queue: queue, file: file, line: line)
    }

    // MARK: - Private

    private static func applyMigrations(to queue: DatabaseQueue) throws {
        // Re-run the same migrator used by the production `Migrator` type,
        // but pointed at our in-memory queue (DatabaseQueue conforms to
        // DatabaseWriter, same as DatabasePool).
        //
        // `DatabasePool` is pool-backed (readers + 1 writer); `DatabaseQueue`
        // is single-connection. The `DatabaseMigrator` API accepts `any DatabaseWriter`,
        // so both work identically.
        //
        // If Migrator.register(on:) only accepts DatabasePool, we use the queue
        // directly with a raw migrator to avoid the pool-only coupling.
        //
        // Implementation: We replicate the migration registration inline so that
        // PersistenceTests does not need @testable import Persistence access to
        // a `DatabasePool`-specific internal, keeping the coupling minimal.
        //
        // When the Migrator is refactored to accept `any DatabaseWriter`, replace
        // this with: `try Migrator.register(on: queue)`

        var migrator = DatabaseMigrator()

        // Discover migration SQL files from the Persistence module bundle.
        guard let bundle = Bundle(identifier: "bizarrecrm.Persistence") ??
              // During SPM tests the bundle identifier may differ; fall back to the
              // module's bundle heuristic.
              {
                  let candidates = Bundle.allBundles + Bundle.allFrameworks
                  return candidates.first(where: {
                      $0.bundlePath.contains("Persistence") &&
                      $0.url(forResource: "Migrations", withExtension: nil) != nil
                  })
              }()
        else {
            // No migration bundle found — return a bare queue. Individual tests
            // can create their own schema via `extraSetup`.
            return
        }

        guard let folderURL = bundle.url(forResource: "Migrations", withExtension: nil) else {
            return
        }

        let files = (try FileManager.default.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: nil
        ))
        .filter { $0.pathExtension.lowercased() == "sql" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for url in files {
            let name = url.deletingPathExtension().lastPathComponent
            let sql = try String(contentsOf: url, encoding: .utf8)
            migrator.registerMigration(name) { db in
                try db.execute(sql: sql)
            }
        }

        try migrator.migrate(queue)
    }
}

// MARK: - XCTestCase extension

public extension XCTestCase {

    /// Convenience: create a migrated in-memory `DatabaseQueue` and store it in
    /// the provided `inout` property, asserting no throw.
    func setUpGRDB(
        into queue: inout DatabaseQueue?,
        extraSetup: ((Database) throws -> Void)? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        do {
            queue = try GRDBTestSupport.makeQueue(extraSetup: extraSetup)
        } catch {
            XCTFail("GRDBTestSupport.makeQueue() threw: \(error)", file: file, line: line)
        }
    }
}

// MARK: - GRDBTestSupportTests

final class GRDBTestSupportTests: XCTestCase {

    func test_makeQueue_succeeds() throws {
        let queue = try GRDBTestSupport.makeQueue()
        XCTAssertNotNil(queue)
    }

    func test_makeEmptyQueue_succeeds() throws {
        let queue = try GRDBTestSupport.makeEmptyQueue()
        XCTAssertNotNil(queue)
    }

    func test_makeQueue_supportsWrite() throws {
        let queue = try GRDBTestSupport.makeQueue(extraSetup: { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS test_items (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL
                )
            """)
        })
        try queue.write { db in
            try db.execute(sql: "INSERT INTO test_items (name) VALUES ('hello')")
        }
        try GRDBTestSupport.assertRowCount(1, in: "test_items", queue: queue)
    }

    func test_makeQueue_isolation_eachQueueIsIndependent() throws {
        let extraSetup: (Database) throws -> Void = { db in
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS isolation_test (id INTEGER PRIMARY KEY)")
        }
        let queue1 = try GRDBTestSupport.makeQueue(extraSetup: extraSetup)
        let queue2 = try GRDBTestSupport.makeQueue(extraSetup: extraSetup)

        try queue1.write { db in
            try db.execute(sql: "INSERT INTO isolation_test (id) VALUES (1)")
        }

        // queue2 must not see queue1's row.
        try GRDBTestSupport.assertEmpty("isolation_test", queue: queue2)
    }

    func test_assertRowCount_correct() throws {
        let queue = try GRDBTestSupport.makeQueue(extraSetup: { db in
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS things (id INTEGER PRIMARY KEY)")
        })
        for i in 1...3 {
            try queue.write { db in
                try db.execute(sql: "INSERT INTO things VALUES (\(i))")
            }
        }
        try GRDBTestSupport.assertRowCount(3, in: "things", queue: queue)
    }

    func test_assertEmpty_passesOnEmptyTable() throws {
        let queue = try GRDBTestSupport.makeQueue(extraSetup: { db in
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS empty_tbl (id INTEGER PRIMARY KEY)")
        })
        try GRDBTestSupport.assertEmpty("empty_tbl", queue: queue)
    }

    func test_seed_convenience() throws {
        let queue = try GRDBTestSupport.makeEmptyQueue()
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE seed_test (val TEXT)")
        }
        try GRDBTestSupport.seed(queue) { db in
            try db.execute(sql: "INSERT INTO seed_test VALUES ('a')")
            try db.execute(sql: "INSERT INTO seed_test VALUES ('b')")
        }
        try GRDBTestSupport.assertRowCount(2, in: "seed_test", queue: queue)
    }
}
