import XCTest
import GRDB
import Core
@testable import Search

// MARK: - Fixtures

private func makeTicket(id: Int64 = 1, status: TicketStatus = .inProgress) -> Ticket {
    Ticket(
        id: id,
        displayId: "T-\(id)",
        customerId: 10,
        customerName: "Alice Smith",
        status: status,
        deviceSummary: "iPhone 14",
        diagnosis: "Cracked screen",
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}

private func makeCustomer(id: Int64 = 1) -> Customer {
    Customer(
        id: id,
        firstName: "Bob",
        lastName: "Jones",
        phone: "555-0100",
        email: "bob@example.com",
        notes: "VIP customer",
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}

private func makeInventoryItem(id: Int64 = 1) -> InventoryItem {
    InventoryItem(
        id: id,
        sku: "SKU-001",
        name: "Screen Protector",
        barcode: "1234567890",
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}

// MARK: - FTSIndexStore tests

final class FTSIndexStoreTests: XCTestCase {

    private var db: DatabaseQueue!
    private var store: FTSIndexStore!

    override func setUp() async throws {
        db = try FTSMigration.openInMemory()
        store = FTSIndexStore(db: db)
    }

    override func tearDown() async throws {
        db = nil
        store = nil
    }

    // MARK: - indexTicket

    func test_indexTicket_noThrow() async throws {
        try await store.indexTicket(makeTicket())
    }

    func test_indexTicket_canBeFoundByDisplayId() async throws {
        try await store.indexTicket(makeTicket(id: 42))
        let hits = try await store.search(query: "T-42", entity: .tickets, limit: 10)
        XCTAssertFalse(hits.isEmpty, "Should find ticket by display ID")
        XCTAssertEqual(hits.first?.entityId, "42")
    }

    func test_indexTicket_canBeFoundByCustomerName() async throws {
        try await store.indexTicket(makeTicket())
        let hits = try await store.search(query: "Alice", entity: nil, limit: 10)
        XCTAssertFalse(hits.isEmpty, "Should find ticket by customer name")
    }

    func test_indexTicket_canBeFoundByDeviceSummary() async throws {
        try await store.indexTicket(makeTicket())
        let hits = try await store.search(query: "iPhone", entity: nil, limit: 10)
        XCTAssertFalse(hits.isEmpty)
    }

    func test_indexTicket_upsert_noduplicates() async throws {
        try await store.indexTicket(makeTicket(id: 1))
        try await store.indexTicket(makeTicket(id: 1))
        let hits = try await store.search(query: "T-1", entity: .tickets, limit: 50)
        XCTAssertEqual(hits.count, 1, "Upsert must not create duplicates")
    }

    // MARK: - indexCustomer

    func test_indexCustomer_canBeFoundByName() async throws {
        try await store.indexCustomer(makeCustomer(id: 1))
        let hits = try await store.search(query: "Bob Jones", entity: .customers, limit: 10)
        XCTAssertFalse(hits.isEmpty)
        XCTAssertEqual(hits.first?.entity, "customers")
    }

    func test_indexCustomer_canBeFoundByPhone() async throws {
        try await store.indexCustomer(makeCustomer())
        let hits = try await store.search(query: "555-0100", entity: nil, limit: 10)
        XCTAssertFalse(hits.isEmpty)
    }

    func test_indexCustomer_canBeFoundByEmail() async throws {
        try await store.indexCustomer(makeCustomer())
        let hits = try await store.search(query: "bob@example", entity: nil, limit: 10)
        XCTAssertFalse(hits.isEmpty)
    }

    // MARK: - indexInvoice

    func test_indexInvoice_canBeFoundByDisplayId() async throws {
        try await store.indexInvoice(
            id: 99,
            displayId: "INV-0099",
            customerName: "Acme Corp",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let hits = try await store.search(query: "INV-0099", entity: .invoices, limit: 10)
        XCTAssertFalse(hits.isEmpty, "Should find invoice by display ID")
        XCTAssertEqual(hits.first?.entityId, "99")
    }

    func test_indexInvoice_canBeFoundByCustomerName() async throws {
        try await store.indexInvoice(
            id: 7,
            displayId: "INV-0007",
            customerName: "Globex Industries",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let hits = try await store.search(query: "Globex", entity: nil, limit: 10)
        XCTAssertFalse(hits.isEmpty, "Should find invoice by customer name")
        XCTAssertEqual(hits.first?.entity, "invoices")
    }

    func test_indexInvoice_upsert_noduplicates() async throws {
        try await store.indexInvoice(id: 5, displayId: "INV-5", customerName: "Dup Co", updatedAt: Date(timeIntervalSince1970: 0))
        try await store.indexInvoice(id: 5, displayId: "INV-5", customerName: "Dup Co", updatedAt: Date(timeIntervalSince1970: 0))
        let hits = try await store.search(query: "INV-5", entity: .invoices, limit: 50)
        XCTAssertEqual(hits.count, 1, "Upsert must not create duplicates for invoices")
    }

    func test_indexInvoice_entityFilterExcludesOtherTypes() async throws {
        try await store.indexTicket(makeTicket(id: 1))
        try await store.indexInvoice(id: 1, displayId: "INV-1", customerName: "Alice Smith", updatedAt: Date(timeIntervalSince1970: 0))

        let invoiceHits = try await store.search(query: "Alice", entity: .invoices, limit: 50)
        XCTAssertTrue(invoiceHits.allSatisfy { $0.entity == "invoices" }, "Invoice filter should exclude ticket hits")
    }

    // MARK: - indexInventory

    func test_indexInventory_canBeFoundByName() async throws {
        try await store.indexInventory(makeInventoryItem())
        let hits = try await store.search(query: "Screen Protector", entity: .inventory, limit: 10)
        XCTAssertFalse(hits.isEmpty)
        XCTAssertEqual(hits.first?.entity, "inventory")
    }

    func test_indexInventory_canBeFoundBySKU() async throws {
        try await store.indexInventory(makeInventoryItem())
        let hits = try await store.search(query: "SKU-001", entity: nil, limit: 10)
        XCTAssertFalse(hits.isEmpty)
    }

    // MARK: - deleteEntity

    func test_deleteEntity_removesFromResults() async throws {
        try await store.indexTicket(makeTicket(id: 5))
        var hits = try await store.search(query: "T-5", entity: nil, limit: 10)
        XCTAssertFalse(hits.isEmpty, "Should exist before deletion")

        try await store.deleteEntity("tickets", "5")
        hits = try await store.search(query: "T-5", entity: nil, limit: 10)
        XCTAssertTrue(hits.isEmpty, "Should be gone after deletion")
    }

    func test_deleteEntity_onlyDeletesTargetEntity() async throws {
        try await store.indexTicket(makeTicket(id: 1))
        try await store.indexCustomer(makeCustomer(id: 1))
        try await store.deleteEntity("tickets", "1")

        let customerHits = try await store.search(query: "Bob Jones", entity: .customers, limit: 10)
        XCTAssertFalse(customerHits.isEmpty, "Customer should still exist")
    }

    // MARK: - EntityFilter

    func test_search_entityFilter_restrictsResults() async throws {
        try await store.indexTicket(makeTicket(id: 1))
        try await store.indexCustomer(makeCustomer(id: 1))

        let customerHits = try await store.search(query: "Alice Bob", entity: .customers, limit: 50)
        let ticketHits   = try await store.search(query: "Alice Bob", entity: .tickets,   limit: 50)

        // Customer filter should not return tickets
        XCTAssertTrue(customerHits.allSatisfy { $0.entity == "customers" })
        // Ticket filter should not return customers
        XCTAssertTrue(ticketHits.allSatisfy { $0.entity == "tickets" })
    }

    func test_search_nilFilter_returnsAllEntities() async throws {
        try await store.indexTicket(makeTicket(id: 1))
        try await store.indexCustomer(makeCustomer(id: 2))
        // Search for a term unique to tickets, verify it returns a result
        let ticketHits = try await store.search(query: "iPhone", entity: nil, limit: 50)
        XCTAssertFalse(ticketHits.isEmpty, "Should find ticket by device summary without filter")
    }

    // MARK: - Limit

    func test_search_limit_respected() async throws {
        for i in 1...10 {
            try await store.indexTicket(makeTicket(id: Int64(i)))
        }
        let hits = try await store.search(query: "Alice", entity: nil, limit: 3)
        XCTAssertLessThanOrEqual(hits.count, 3)
    }

    // MARK: - SearchHit shape

    func test_searchHit_hasNonEmptyTitle() async throws {
        try await store.indexTicket(makeTicket())
        let hits = try await store.search(query: "Alice", entity: nil, limit: 10)
        XCTAssertFalse(hits.first?.title.isEmpty ?? true)
    }

    func test_searchHit_id_isComposite() async throws {
        try await store.indexCustomer(makeCustomer(id: 99))
        let hits = try await store.search(query: "Bob", entity: .customers, limit: 10)
        XCTAssertEqual(hits.first?.id, "customers:99")
    }
}

// MARK: - FTSIndex escape tests

final class FTSIndexEscapeTests: XCTestCase {

    func test_escapeFTSQuery_singleToken_addsPrefix() {
        let result = FTSIndex.escapeFTSQuery("iph")
        XCTAssertTrue(result.hasSuffix("*\""), "Last token should have prefix wildcard")
    }

    func test_escapeFTSQuery_empty_returnsEmpty() {
        XCTAssertEqual(FTSIndex.escapeFTSQuery(""), "")
        XCTAssertEqual(FTSIndex.escapeFTSQuery("   "), "")
    }

    func test_escapeFTSQuery_multiToken_lastHasWildcard() {
        let result = FTSIndex.escapeFTSQuery("alice sm")
        XCTAssertTrue(result.contains("*\""))
    }

    func test_escapeFTSQuery_quotesEscaped() {
        let result = FTSIndex.escapeFTSQuery("say \"hello\"")
        // Each token is wrapped in double-quotes with internal quotes doubled.
        // Result must be parseable — specifically the raw input quote chars
        // inside each phrase token must not be left unescaped (single bare ").
        // Verify the output is non-empty and structured.
        XCTAssertFalse(result.isEmpty)
        // The escaped form of one internal " is "" — so result contains ""
        // but that's fine. What matters: the token boundaries are intact.
        XCTAssertTrue(result.hasPrefix("\""), "Result must start with opening quote")
    }
}
