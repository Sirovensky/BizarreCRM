import XCTest
import GRDB
import Core
@testable import Search

// MARK: - ScopeCounts unit tests

final class ScopeCountsTests: XCTestCase {

    // MARK: - from(localHits:)

    func test_fromLocalHits_emptyArray_returnsZero() {
        let counts = ScopeCounts.from(localHits: [])
        XCTAssertEqual(counts, .zero)
    }

    func test_fromLocalHits_countsPerEntity() {
        let hits: [SearchHit] = [
            SearchHit(entity: "customers",    entityId: "1", title: "A", snippet: "", score: 0),
            SearchHit(entity: "customers",    entityId: "2", title: "B", snippet: "", score: 0),
            SearchHit(entity: "tickets",      entityId: "3", title: "C", snippet: "", score: 0),
            SearchHit(entity: "inventory",    entityId: "4", title: "D", snippet: "", score: 0),
            SearchHit(entity: "invoices",     entityId: "5", title: "E", snippet: "", score: 0),
        ]
        let counts = ScopeCounts.from(localHits: hits)
        XCTAssertEqual(counts.customers, 2)
        XCTAssertEqual(counts.tickets, 1)
        XCTAssertEqual(counts.inventory, 1)
        XCTAssertEqual(counts.invoices, 1)
        XCTAssertEqual(counts.all, 5)
    }

    func test_fromLocalHits_unknownEntity_ignored() {
        let hit = SearchHit(entity: "unknown", entityId: "1", title: "X", snippet: "", score: 0)
        let counts = ScopeCounts.from(localHits: [hit])
        XCTAssertEqual(counts.all, 0)
    }

    // MARK: - count(for:)

    func test_countForFilter_all_returnsAllCount() {
        let counts = ScopeCounts(all: 7)
        XCTAssertEqual(counts.count(for: .all), 7)
    }

    func test_countForFilter_customers_returnsCustomerCount() {
        let counts = ScopeCounts(customers: 3)
        XCTAssertEqual(counts.count(for: .customers), 3)
    }

    func test_countForFilter_tickets_returnsTicketCount() {
        let counts = ScopeCounts(tickets: 5)
        XCTAssertEqual(counts.count(for: .tickets), 5)
    }

    // MARK: - merged(with:)

    func test_merged_takesMaxPerEntity() {
        let local = ScopeCounts(customers: 2, tickets: 8)
        let remote = makeRemoteResults(customers: 5, tickets: 3)
        let merged = local.merged(with: remote)
        XCTAssertEqual(merged.customers, 5, "Remote count (5) > local (2) → take remote")
        XCTAssertEqual(merged.tickets, 8, "Local count (8) > remote (3) → keep local")
    }

    func test_merged_zeroLocal_usesRemote() {
        let local = ScopeCounts.zero
        let remote = makeRemoteResults(customers: 4, tickets: 2, inventory: 1, invoices: 3)
        let merged = local.merged(with: remote)
        XCTAssertEqual(merged.customers, 4)
        XCTAssertEqual(merged.tickets, 2)
        XCTAssertEqual(merged.inventory, 1)
        XCTAssertEqual(merged.invoices, 3)
    }

    func test_merged_allCountEqualsSum() {
        let local = ScopeCounts(customers: 2, tickets: 1)
        let remote = makeRemoteResults(customers: 3, tickets: 1, inventory: 2, invoices: 0)
        let merged = local.merged(with: remote)
        // all = max(2,3) + max(1,1) + max(0,2) + max(0,0) = 3 + 1 + 2 + 0 = 6
        XCTAssertEqual(merged.all, 6)
    }

    // MARK: - zero sentinel

    func test_zero_allFieldsAreZero() {
        let z = ScopeCounts.zero
        XCTAssertEqual(z.all, 0)
        XCTAssertEqual(z.customers, 0)
        XCTAssertEqual(z.tickets, 0)
        XCTAssertEqual(z.inventory, 0)
        XCTAssertEqual(z.invoices, 0)
        XCTAssertEqual(z.estimates, 0)
        XCTAssertEqual(z.appointments, 0)
    }

    // MARK: - FTSIndexStore.scopeCounts integration

    func test_ftsStore_scopeCounts_returnsCorrectCounts() async throws {
        let db = try IsolatedFTSDatabase.openInMemory()
        let store = FTSIndexStore(db: db)

        try await store.indexTicket(Ticket(
            id: 1, displayId: "T-1", customerId: 1, customerName: "Alice",
            status: .inProgress, deviceSummary: "iPhone",
            createdAt: .now, updatedAt: .now
        ))
        try await store.indexCustomer(Customer(
            id: 1, firstName: "Alice", lastName: "Smith",
            createdAt: .now, updatedAt: .now
        ))

        let counts = try await store.scopeCounts(query: "Alice")
        // Both a ticket (by customerName) and a customer should be found.
        XCTAssertGreaterThan(counts.all, 0)
    }

    func test_ftsStore_scopeCounts_emptyQuery_returnsZero() async throws {
        let db = try IsolatedFTSDatabase.openInMemory()
        let store = FTSIndexStore(db: db)
        let counts = try await store.scopeCounts(query: "")
        XCTAssertEqual(counts, .zero)
    }

    // MARK: - Helpers

    private func makeRemoteResults(
        customers: Int = 0,
        tickets: Int = 0,
        inventory: Int = 0,
        invoices: Int = 0
    ) -> GlobalSearchResults {
        let customerRows = (0..<customers).map { GlobalSearchResults.Row(id: Int64($0), display: "C\($0)", type: "customer", subtitle: nil) }
        let ticketRows   = (0..<tickets).map   { GlobalSearchResults.Row(id: Int64($0 + 100), display: "T\($0)", type: "ticket", subtitle: nil) }
        let inventoryRows = (0..<inventory).map { GlobalSearchResults.Row(id: Int64($0 + 200), display: "I\($0)", type: "inventory", subtitle: nil) }
        let invoiceRows  = (0..<invoices).map  { GlobalSearchResults.Row(id: Int64($0 + 300), display: "V\($0)", type: "invoice", subtitle: nil) }
        return GlobalSearchResults(
            customers: customerRows,
            tickets: ticketRows,
            inventory: inventoryRows,
            invoices: invoiceRows
        )
    }
}
