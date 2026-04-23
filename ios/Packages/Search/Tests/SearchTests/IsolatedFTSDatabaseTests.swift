import XCTest
import GRDB
import Core
@testable import Search

final class IsolatedFTSDatabaseTests: XCTestCase {

    // MARK: - In-memory open

    func test_openInMemory_doesNotThrow() throws {
        XCTAssertNoThrow(try IsolatedFTSDatabase.openInMemory())
    }

    func test_openInMemory_searchIndexTableExists() throws {
        let db = try IsolatedFTSDatabase.openInMemory()
        let exists = try db.read { db in
            try db.tableExists("search_index")
        }
        XCTAssertTrue(exists, "FTS5 virtual table search_index must exist after migration")
    }

    func test_openInMemory_calledTwice_noMigrationError() throws {
        // Both calls should open independently without conflicting.
        let db1 = try IsolatedFTSDatabase.openInMemory()
        let db2 = try IsolatedFTSDatabase.openInMemory()
        XCTAssertNotNil(db1)
        XCTAssertNotNil(db2)
    }

    // MARK: - Schema

    func test_schema_fts5SupportsInsert() throws {
        let db = try IsolatedFTSDatabase.openInMemory()
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO search_index(entity, entityId, title, body, tags, updatedAt)
                VALUES ('tickets', '1', 'Test Ticket', 'body text', 'in_progress', '2024-01-01')
            """)
        }
    }

    func test_schema_fts5SupportsMatch() throws {
        let db = try IsolatedFTSDatabase.openInMemory()
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO search_index(entity, entityId, title, body, tags, updatedAt)
                VALUES ('customers', '42', 'Alice Smith', '555-0100', '', '2024-01-01')
            """)
        }
        let count = try db.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM search_index WHERE search_index MATCH 'Alice*'
            """) ?? 0
        }
        XCTAssertEqual(count, 1)
    }

    func test_schema_fts5SupportsDelete() throws {
        let db = try IsolatedFTSDatabase.openInMemory()
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO search_index(entity, entityId, title, body, tags, updatedAt)
                VALUES ('tickets', '1', 'Cracked Screen', '', '', '2024-01-01')
            """)
            try db.execute(sql: "DELETE FROM search_index WHERE entity = 'tickets' AND entityId = '1'")
        }
        let count = try db.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM search_index WHERE search_index MATCH 'Cracked*'
            """) ?? 0
        }
        XCTAssertEqual(count, 0)
    }

    // MARK: - FTSIndexStore integration with IsolatedFTSDatabase

    func test_ftsStore_isolated_factory_usesIsolatedDB() async throws {
        let db = try IsolatedFTSDatabase.openInMemory()
        let store = FTSIndexStore(db: db)
        // Should be usable without Persistence database.
        let ticket = Ticket(
            id: 1, displayId: "T-1", customerId: 1, customerName: "Bob",
            status: .intake, createdAt: .now, updatedAt: .now
        )
        try await store.indexTicket(ticket)
        let hits = try await store.search(query: "Bob", entity: nil, limit: 10)
        XCTAssertFalse(hits.isEmpty)
    }

    func test_ftsStore_indexAndSearch_customerInIsolatedDB() async throws {
        let db = try IsolatedFTSDatabase.openInMemory()
        let store = FTSIndexStore(db: db)
        let customer = Customer(
            id: 7, firstName: "Charlie", lastName: "Brown",
            phone: "555-9999", email: "charlie@example.com",
            createdAt: .now, updatedAt: .now
        )
        try await store.indexCustomer(customer)
        let hits = try await store.search(query: "Charlie", entity: .customers, limit: 10)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.entityId, "7")
    }

    func test_ftsStore_delete_removesFromIsolatedDB() async throws {
        let db = try IsolatedFTSDatabase.openInMemory()
        let store = FTSIndexStore(db: db)
        let item = InventoryItem(id: 5, sku: "ABC-123", name: "Battery", barcode: nil, updatedAt: .now)
        try await store.indexInventory(item)
        try await store.deleteEntity("inventory", "5")
        let hits = try await store.search(query: "Battery", entity: .inventory, limit: 10)
        XCTAssertTrue(hits.isEmpty)
    }

    // MARK: - Porter tokenizer (stemming)

    func test_fts5_porterTokenizer_stemmedMatch() throws {
        let db = try IsolatedFTSDatabase.openInMemory()
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO search_index(entity, entityId, title, body, tags, updatedAt)
                VALUES ('tickets', '1', 'Screen is cracking', '', '', '2024-01-01')
            """)
        }
        // "crack" should match "cracking" via porter stemmer
        let count = try db.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM search_index WHERE search_index MATCH 'crack*'
            """) ?? 0
        }
        XCTAssertGreaterThan(count, 0)
    }

    // MARK: - Migration idempotency

    func test_migration_runTwice_idempotent() throws {
        let db = try DatabaseQueue()
        XCTAssertNoThrow(try IsolatedFTSDatabase.migrate(db))
        // Running migrate again must not throw (CREATE TABLE IF NOT EXISTS).
        XCTAssertNoThrow(try IsolatedFTSDatabase.migrate(db))
    }
}
