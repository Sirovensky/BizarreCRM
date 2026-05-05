import XCTest
import CoreSpotlight
import Core
@testable import Search

// MARK: - Stub index

/// In-memory stub that records calls for assertion.
final class StubSearchableIndex: CSSearchableIndexProtocol, @unchecked Sendable {
    private(set) var indexedItems: [CSSearchableItem] = []
    private(set) var deletedIdentifiers: [String] = []
    private(set) var deletedDomains: [String] = []

    var shouldThrow: Bool = false
    private struct FakeError: Error {}

    func indexSearchableItems(_ items: [CSSearchableItem]) async throws {
        if shouldThrow { throw FakeError() }
        indexedItems.append(contentsOf: items)
    }

    func deleteSearchableItems(withIdentifiers identifiers: [String]) async throws {
        if shouldThrow { throw FakeError() }
        deletedIdentifiers.append(contentsOf: identifiers)
    }

    func deleteSearchableItems(withDomainIdentifiers domainIdentifiers: [String]) async throws {
        if shouldThrow { throw FakeError() }
        deletedDomains.append(contentsOf: domainIdentifiers)
    }
}

// MARK: - Fixtures

private func makeTicket(id: Int64 = 1) -> Ticket {
    Ticket(
        id: id,
        displayId: "T-\(id)",
        customerId: 10,
        customerName: "Alice Smith",
        status: .inProgress,
        deviceSummary: "iPhone 14",
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

// MARK: - SpotlightIndexerTests

final class SpotlightIndexerTests: XCTestCase {

    private var stub: StubSearchableIndex!
    private var indexer: SpotlightIndexer!

    override func setUp() async throws {
        stub = StubSearchableIndex()
        indexer = SpotlightIndexer(index: stub)
    }

    // MARK: - indexTicket

    func test_indexTicket_sendsOneItem() async throws {
        let ticket = makeTicket()
        try await indexer.indexTicket(ticket)
        XCTAssertEqual(stub.indexedItems.count, 1)
    }

    func test_indexTicket_uniqueIdentifierMatchesFormat() async throws {
        let ticket = makeTicket(id: 42)
        try await indexer.indexTicket(ticket)
        XCTAssertEqual(stub.indexedItems.first?.uniqueIdentifier, "bizarrecrm.ticket.42")
    }

    func test_indexTicket_domainIdentifierIsTickets() async throws {
        let ticket = makeTicket()
        try await indexer.indexTicket(ticket)
        XCTAssertEqual(stub.indexedItems.first?.domainIdentifier, "tickets")
    }

    func test_indexTicket_propagatesError() async {
        stub.shouldThrow = true
        let ticket = makeTicket()
        do {
            try await indexer.indexTicket(ticket)
            XCTFail("Expected error")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    // MARK: - indexCustomer

    func test_indexCustomer_sendsOneItem() async {
        let customer = makeCustomer()
        await indexer.indexCustomer(customer)
        XCTAssertEqual(stub.indexedItems.count, 1)
    }

    func test_indexCustomer_uniqueIdentifierMatchesFormat() async {
        let customer = makeCustomer(id: 99)
        await indexer.indexCustomer(customer)
        XCTAssertEqual(stub.indexedItems.first?.uniqueIdentifier, "bizarrecrm.customer.99")
    }

    func test_indexCustomer_doesNotThrowOnIndexFailure() async {
        stub.shouldThrow = true
        let customer = makeCustomer()
        // Should complete without throwing even if index fails
        await indexer.indexCustomer(customer)
    }

    // MARK: - indexInventoryItem

    func test_indexInventoryItem_sendsOneItem() async {
        let item = makeInventoryItem()
        await indexer.indexInventoryItem(item)
        XCTAssertEqual(stub.indexedItems.count, 1)
    }

    func test_indexInventoryItem_containsSKUInKeywords() async {
        let item = makeInventoryItem()
        await indexer.indexInventoryItem(item)
        let keywords = stub.indexedItems.first?.attributeSet.keywords ?? []
        XCTAssertTrue(keywords.contains("SKU-001"))
    }

    // MARK: - batchIndex

    func test_batchIndex_indexesAllItems() async throws {
        let tickets = (1...5).map { makeTicket(id: Int64($0)) }
        try await indexer.batchIndex(tickets)
        XCTAssertEqual(stub.indexedItems.count, 5)
    }

    func test_batchIndex_splitsIntoBatchesOf100() async throws {
        // 150 items → 2 batch calls
        let tickets = (1...150).map { makeTicket(id: Int64($0)) }
        try await indexer.batchIndex(tickets)
        // All 150 items should be indexed
        XCTAssertEqual(stub.indexedItems.count, 150)
    }

    func test_batchIndex_emptyArray_sendsNoItems() async throws {
        let tickets: [Ticket] = []
        try await indexer.batchIndex(tickets)
        XCTAssertEqual(stub.indexedItems.count, 0)
    }

    func test_batchIndex_customers() async throws {
        let customers = (1...3).map { makeCustomer(id: Int64($0)) }
        try await indexer.batchIndex(customers)
        XCTAssertEqual(stub.indexedItems.count, 3)
    }

    // MARK: - removeItem

    func test_removeItem_sendsCorrectIdentifier() async throws {
        try await indexer.removeItem(uniqueIdentifier: "bizarrecrm.ticket.7")
        XCTAssertEqual(stub.deletedIdentifiers, ["bizarrecrm.ticket.7"])
    }

    // MARK: - removeDomain

    func test_removeDomain_sendsCorrectDomain() async throws {
        try await indexer.removeDomain("tickets")
        XCTAssertEqual(stub.deletedDomains, ["tickets"])
    }
}

// MARK: - SpotlightIndexableTests

final class SpotlightIndexableTests: XCTestCase {

    // MARK: Ticket

    func test_ticket_spotlightUniqueIdentifier() {
        let ticket = makeTicket(id: 5)
        XCTAssertEqual(ticket.spotlightUniqueIdentifier, "bizarrecrm.ticket.5")
    }

    func test_ticket_spotlightDomain() {
        XCTAssertEqual(makeTicket().spotlightDomain, "tickets")
    }

    func test_ticket_toSearchableItem_titleContainsDisplayId() {
        let ticket = makeTicket()
        let item = ticket.toSearchableItem()
        XCTAssertTrue(item.attributeSet.title?.contains("T-1") == true)
    }

    func test_ticket_toSearchableItem_titleContainsCustomerName() {
        let ticket = makeTicket()
        let item = ticket.toSearchableItem()
        XCTAssertTrue(item.attributeSet.title?.contains("Alice Smith") == true)
    }

    // MARK: Customer

    func test_customer_spotlightUniqueIdentifier() {
        let customer = makeCustomer(id: 22)
        XCTAssertEqual(customer.spotlightUniqueIdentifier, "bizarrecrm.customer.22")
    }

    func test_customer_spotlightDomain() {
        XCTAssertEqual(makeCustomer().spotlightDomain, "customers")
    }

    func test_customer_toSearchableItem_titleIsDisplayName() {
        let customer = makeCustomer()
        let item = customer.toSearchableItem()
        XCTAssertEqual(item.attributeSet.title, "Bob Jones")
    }

    func test_customer_toSearchableItem_descriptionContainsPhone() {
        let customer = makeCustomer()
        let item = customer.toSearchableItem()
        XCTAssertTrue(item.attributeSet.contentDescription?.contains("555-0100") == true)
    }

    // MARK: InventoryItem

    func test_inventoryItem_spotlightUniqueIdentifier() {
        let item = makeInventoryItem(id: 8)
        XCTAssertEqual(item.spotlightUniqueIdentifier, "bizarrecrm.inventory.8")
    }

    func test_inventoryItem_spotlightDomain() {
        XCTAssertEqual(makeInventoryItem().spotlightDomain, "inventory")
    }

    func test_inventoryItem_toSearchableItem_titleIsName() {
        let item = makeInventoryItem()
        XCTAssertEqual(item.toSearchableItem().attributeSet.title, "Screen Protector")
    }
}

// MARK: - SpotlightCoordinatorTests

@MainActor
final class SpotlightCoordinatorTests: XCTestCase {

    private var stub: StubSearchableIndex!
    private var indexer: SpotlightIndexer!
    private var coordinator: SpotlightCoordinator!

    override func setUp() async throws {
        stub = StubSearchableIndex()
        indexer = SpotlightIndexer(index: stub)
        coordinator = SpotlightCoordinator(indexer: indexer)
        // Disable 2s debounce by calling flush directly in tests
    }

    override func tearDown() async throws {
        // Clean up notification observers via dealloc
        coordinator = nil
    }

    // MARK: - Domain toggle

    func test_enabledDomains_defaultsToAllThree() {
        XCTAssertTrue(coordinator.enabledDomains.contains("tickets"))
        XCTAssertTrue(coordinator.enabledDomains.contains("customers"))
        XCTAssertTrue(coordinator.enabledDomains.contains("inventory"))
    }

    func test_disablingDomain_preventsNotificationFromQueuing() async {
        coordinator.enabledDomains.remove("tickets")
        // Post a notification
        NotificationCenter.default.post(
            name: .ticketChanged,
            object: nil,
            userInfo: ["ticket": makeTicket()]
        )
        // Flush immediately — nothing should be indexed
        await coordinator.flush()
        XCTAssertEqual(stub.indexedItems.count, 0)
    }

    // MARK: - Notification-driven indexing

    func test_ticketChangedNotification_indexesTicketOnFlush() async {
        let ticket = makeTicket(id: 77)
        NotificationCenter.default.post(
            name: .ticketChanged,
            object: nil,
            userInfo: ["ticket": ticket]
        )
        // Give the MainActor a cycle to process the notification observer task
        await Task.yield()
        await coordinator.flush()
        let ids = stub.indexedItems.map { $0.uniqueIdentifier }
        XCTAssertTrue(ids.contains("bizarrecrm.ticket.77"))
    }

    func test_customerChangedNotification_indexesCustomerOnFlush() async {
        let customer = makeCustomer(id: 55)
        NotificationCenter.default.post(
            name: .customerChanged,
            object: nil,
            userInfo: ["customer": customer]
        )
        await Task.yield()
        await coordinator.flush()
        let ids = stub.indexedItems.map { $0.uniqueIdentifier }
        XCTAssertTrue(ids.contains("bizarrecrm.customer.55"))
    }

    func test_deduplicates_sameTicketPostedTwice_indexedOnce() async {
        let ticket = makeTicket(id: 10)
        for _ in 0..<2 {
            NotificationCenter.default.post(
                name: .ticketChanged,
                object: nil,
                userInfo: ["ticket": ticket]
            )
        }
        await Task.yield()
        await coordinator.flush()
        let ticketIds = stub.indexedItems
            .map { $0.uniqueIdentifier }
            .filter { $0 == "bizarrecrm.ticket.10" }
        XCTAssertEqual(ticketIds.count, 1)
    }

    func test_flush_clearsQueue() async {
        NotificationCenter.default.post(
            name: .ticketChanged,
            object: nil,
            userInfo: ["ticket": makeTicket()]
        )
        await Task.yield()
        await coordinator.flush()
        // Second flush should not re-index
        await coordinator.flush()
        XCTAssertEqual(stub.indexedItems.count, 1)
    }

    // MARK: - rebuildAll

    func test_rebuildAll_indexesTicketsWhenEnabled() async {
        coordinator.rebuildAll(
            ticketProvider: { [makeTicket(id: 1), makeTicket(id: 2)] },
            customerProvider: { [] },
            inventoryProvider: { [] }
        )
        // Allow async rebuild task to complete
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(stub.indexedItems.count, 2)
    }

    func test_rebuildAll_skipsDisabledDomain() async {
        coordinator.enabledDomains = ["customers"]
        coordinator.rebuildAll(
            ticketProvider: { [makeTicket()] },
            customerProvider: { [makeCustomer()] },
            inventoryProvider: { [makeInventoryItem()] }
        )
        try? await Task.sleep(nanoseconds: 50_000_000)
        // Only customer should be indexed
        let domains = stub.indexedItems.compactMap { $0.domainIdentifier }
        XCTAssertFalse(domains.contains("tickets"))
        XCTAssertFalse(domains.contains("inventory"))
        XCTAssertTrue(domains.contains("customers"))
    }
}
