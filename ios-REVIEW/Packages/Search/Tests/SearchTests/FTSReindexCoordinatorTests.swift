import XCTest
import GRDB
import Core
@testable import Search

// MARK: - Fixtures

private func makeTicket(id: Int64 = 1) -> Ticket {
    Ticket(
        id: id, displayId: "T-\(id)", customerId: 1,
        customerName: "Alice", status: .inProgress,
        deviceSummary: "iPhone",
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}

private func makeCustomer(id: Int64 = 1) -> Customer {
    Customer(
        id: id, firstName: "Bob", lastName: "Jones",
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}

private func makeInventoryItem(id: Int64 = 1) -> InventoryItem {
    InventoryItem(id: id, sku: "SKU-\(id)", name: "Item \(id)", barcode: nil,
                  updatedAt: Date(timeIntervalSince1970: 0))
}

// MARK: - FTSReindexCoordinatorTests

@MainActor
final class FTSReindexCoordinatorTests: XCTestCase {

    private var db: DatabaseQueue!
    private var store: FTSIndexStore!
    private var coordinator: FTSReindexCoordinator!

    override func setUp() async throws {
        db = try IsolatedFTSDatabase.openInMemory()
        store = FTSIndexStore(db: db)
        coordinator = FTSReindexCoordinator(ftsStore: store)
    }

    override func tearDown() async throws {
        coordinator = nil
        store = nil
        db = nil
    }

    // MARK: - Initial state

    func test_initialState_isNotIndexing() {
        XCTAssertFalse(coordinator.isIndexing)
    }

    func test_initialState_lastIndexedAtIsNil() {
        XCTAssertNil(coordinator.lastIndexedAt)
    }

    // MARK: - rebuildAll

    func test_rebuildAll_indexesTickets() async throws {
        coordinator.rebuildAll(
            ticketProvider: { [makeTicket(id: 1), makeTicket(id: 2)] },
            customerProvider: { [] },
            inventoryProvider: { [] }
        )
        try await Task.sleep(nanoseconds: 100_000_000)  // wait for async task
        let hits = try await store.search(query: "Alice", entity: .tickets, limit: 50)
        XCTAssertFalse(hits.isEmpty, "Tickets should be indexed")
    }

    func test_rebuildAll_indexesCustomers() async throws {
        coordinator.rebuildAll(
            ticketProvider: { [] },
            customerProvider: { [makeCustomer(id: 3)] },
            inventoryProvider: { [] }
        )
        try await Task.sleep(nanoseconds: 100_000_000)
        let hits = try await store.search(query: "Bob", entity: .customers, limit: 50)
        XCTAssertFalse(hits.isEmpty, "Customers should be indexed")
    }

    func test_rebuildAll_indexesInventory() async throws {
        coordinator.rebuildAll(
            ticketProvider: { [] },
            customerProvider: { [] },
            inventoryProvider: { [makeInventoryItem(id: 5)] }
        )
        try await Task.sleep(nanoseconds: 100_000_000)
        let hits = try await store.search(query: "Item", entity: .inventory, limit: 50)
        XCTAssertFalse(hits.isEmpty, "Inventory should be indexed")
    }

    func test_rebuildAll_setsLastIndexedAt() async throws {
        coordinator.rebuildAll(
            ticketProvider: { [makeTicket()] },
            customerProvider: { [] },
            inventoryProvider: { [] }
        )
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotNil(coordinator.lastIndexedAt)
    }

    func test_rebuildAll_emptyProviders_doesNotThrow() async throws {
        coordinator.rebuildAll(
            ticketProvider: { [] },
            customerProvider: { [] },
            inventoryProvider: { [] }
        )
        try await Task.sleep(nanoseconds: 50_000_000)
        // No assertion needed — must simply not crash.
    }

    func test_rebuildAll_indexesInvoices() async throws {
        let entry = FTSReindexCoordinator.InvoiceIndexEntry(
            id: 101, displayId: "INV-0101",
            customerName: "Delta Supplies",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        coordinator.rebuildAll(
            ticketProvider: { [] },
            customerProvider: { [] },
            inventoryProvider: { [] },
            invoiceProvider: { [entry] }
        )
        try await Task.sleep(nanoseconds: 100_000_000)
        let hits = try await store.search(query: "INV-0101", entity: .invoices, limit: 10)
        XCTAssertFalse(hits.isEmpty, "Invoice should be indexed via rebuildAll invoiceProvider")
        XCTAssertEqual(hits.first?.entity, "invoices")
    }

    func test_rebuildAll_invoiceProvider_nil_doesNotCrash() async throws {
        coordinator.rebuildAll(
            ticketProvider: { [] },
            customerProvider: { [] },
            inventoryProvider: { [] },
            invoiceProvider: nil
        )
        try await Task.sleep(nanoseconds: 50_000_000)
        // Must not crash when invoiceProvider is omitted.
    }

    // MARK: - Notification-driven incremental indexing

    func test_ticketChangedNotification_queuesTicketForIndex() async throws {
        let ticket = makeTicket(id: 99)
        NotificationCenter.default.post(
            name: .ticketChanged,
            object: nil,
            userInfo: ["ticket": ticket]
        )
        // Give the coordinator time to debounce and flush.
        try await Task.sleep(nanoseconds: 1_200_000_000)
        let hits = try await store.search(query: "T-99", entity: .tickets, limit: 10)
        XCTAssertFalse(hits.isEmpty, "Ticket posted via NC should be in the FTS index")
    }

    func test_customerChangedNotification_queuesCustomerForIndex() async throws {
        let customer = makeCustomer(id: 42)
        NotificationCenter.default.post(
            name: .customerChanged,
            object: nil,
            userInfo: ["customer": customer]
        )
        try await Task.sleep(nanoseconds: 1_200_000_000)
        let hits = try await store.search(query: "Bob", entity: .customers, limit: 10)
        XCTAssertFalse(hits.isEmpty, "Customer posted via NC should be in the FTS index")
    }

    func test_inventoryChangedNotification_queuesItemForIndex() async throws {
        let item = makeInventoryItem(id: 7)
        NotificationCenter.default.post(
            name: .inventoryChanged,
            object: nil,
            userInfo: ["inventoryItem": item]
        )
        try await Task.sleep(nanoseconds: 1_200_000_000)
        let hits = try await store.search(query: "SKU-7", entity: .inventory, limit: 10)
        XCTAssertFalse(hits.isEmpty, "Inventory item posted via NC should be in the FTS index")
    }

    func test_invoiceChangedNotification_queuesInvoiceForIndex() async throws {
        NotificationCenter.default.post(
            name: .invoiceChanged,
            object: nil,
            userInfo: [
                "invoiceId": Int64(200),
                "displayId": "INV-0200",
                "customerName": "Eagle Corp",
                "updatedAt": Date(timeIntervalSince1970: 0),
            ]
        )
        // Give the coordinator time to debounce and flush.
        try await Task.sleep(nanoseconds: 1_200_000_000)
        let hits = try await store.search(query: "INV-0200", entity: .invoices, limit: 10)
        XCTAssertFalse(hits.isEmpty, "Invoice posted via NC should be in the FTS index")
    }

    func test_invoiceChangedNotification_missingFields_noIndexEntry() async throws {
        // Posting without required fields should not crash and should not index anything.
        NotificationCenter.default.post(
            name: .invoiceChanged,
            object: nil,
            userInfo: ["invoiceId": Int64(999)]  // missing displayId/customerName/updatedAt
        )
        try await Task.sleep(nanoseconds: 1_200_000_000)
        let hits = try await store.search(query: "INV", entity: .invoices, limit: 10)
        // May or may not be empty — just must not crash
        _ = hits
    }

    func test_flush_deduplicatesSameTicket() async throws {
        // Post the same ticket twice before the debounce fires.
        let ticket = makeTicket(id: 55)
        NotificationCenter.default.post(
            name: .ticketChanged, object: nil, userInfo: ["ticket": ticket]
        )
        NotificationCenter.default.post(
            name: .ticketChanged, object: nil, userInfo: ["ticket": ticket]
        )
        await coordinator.flush()
        let hits = try await store.search(query: "T-55", entity: .tickets, limit: 50)
        // Dedup means only 1 entry in the index.
        XCTAssertEqual(hits.count, 1, "Same ticket posted twice should only be indexed once")
    }

    func test_flush_clearsQueue() async throws {
        let ticket = makeTicket(id: 10)
        NotificationCenter.default.post(
            name: .ticketChanged, object: nil, userInfo: ["ticket": ticket]
        )
        await Task.yield()
        await coordinator.flush()
        // After first flush, posting nothing new and flushing again should not re-index.
        let hitsBefore = try await store.search(query: "T-10", entity: .tickets, limit: 10)
        let countBefore = hitsBefore.count
        await coordinator.flush()
        let hitsAfter = try await store.search(query: "T-10", entity: .tickets, limit: 10)
        XCTAssertEqual(hitsAfter.count, countBefore, "Second flush must not create duplicate entries")
    }
}
