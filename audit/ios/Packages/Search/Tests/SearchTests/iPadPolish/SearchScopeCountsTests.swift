import XCTest
@testable import Search

/// §22 — Unit tests for `SearchScopeCounts`.
final class SearchScopeCountsTests: XCTestCase {

    // MARK: - .zero

    func test_zero_allCountsAreZero() {
        let zero = SearchScopeCounts.zero
        XCTAssertEqual(zero.all, 0)
        XCTAssertEqual(zero.customers, 0)
        XCTAssertEqual(zero.tickets, 0)
        XCTAssertEqual(zero.inventory, 0)
        XCTAssertEqual(zero.invoices, 0)
        XCTAssertEqual(zero.notes, 0)
    }

    func test_zero_countForAllScopesIsZero() {
        let zero = SearchScopeCounts.zero
        for scope in SearchScope.allCases {
            XCTAssertEqual(zero.count(for: scope), 0, "\(scope) should be 0 in .zero")
        }
    }

    // MARK: - count(for:)

    func test_countFor_returnsCorrectPerScope() {
        let counts = SearchScopeCounts(
            all: 10,
            customers: 3,
            tickets: 2,
            inventory: 1,
            invoices: 4,
            notes: 0
        )
        XCTAssertEqual(counts.count(for: .all), 10)
        XCTAssertEqual(counts.count(for: .customers), 3)
        XCTAssertEqual(counts.count(for: .tickets), 2)
        XCTAssertEqual(counts.count(for: .inventory), 1)
        XCTAssertEqual(counts.count(for: .invoices), 4)
        XCTAssertEqual(counts.count(for: .notes), 0)
    }

    // MARK: - from(hits:)

    func test_fromHits_countsCustomers() {
        let hits = [
            makeHit(entity: "customers", id: "1"),
            makeHit(entity: "customers", id: "2"),
            makeHit(entity: "tickets",   id: "3"),
        ]
        let counts = SearchScopeCounts.from(hits: hits)
        XCTAssertEqual(counts.customers, 2)
        XCTAssertEqual(counts.tickets, 1)
        XCTAssertEqual(counts.inventory, 0)
        XCTAssertEqual(counts.invoices, 0)
        XCTAssertEqual(counts.notes, 0)
    }

    func test_fromHits_allIsSum() {
        let hits = [
            makeHit(entity: "customers", id: "1"),
            makeHit(entity: "invoices",  id: "2"),
            makeHit(entity: "notes",     id: "3"),
        ]
        let counts = SearchScopeCounts.from(hits: hits)
        XCTAssertEqual(counts.all, 3)
    }

    func test_fromHits_unknownEntityIsIgnored() {
        let hits = [makeHit(entity: "unknown_entity", id: "x")]
        let counts = SearchScopeCounts.from(hits: hits)
        XCTAssertEqual(counts.all, 0)
    }

    func test_fromHits_emptyHitsReturnsZero() {
        let counts = SearchScopeCounts.from(hits: [])
        XCTAssertEqual(counts, .zero)
    }

    // MARK: - merged(with:)

    func test_merged_takesMaxPerEntity() {
        let local = SearchScopeCounts(
            all: 3, customers: 2, tickets: 1,
            inventory: 0, invoices: 0, notes: 0
        )
        let fts = ScopeCounts(
            all: 5, customers: 1, tickets: 3,
            inventory: 1, invoices: 0, estimates: 0, appointments: 0
        )
        let merged = local.merged(with: fts)
        XCTAssertEqual(merged.customers, 2,  "max(2, 1) = 2")
        XCTAssertEqual(merged.tickets,   3,  "max(1, 3) = 3")
        XCTAssertEqual(merged.inventory, 1,  "max(0, 1) = 1")
        XCTAssertEqual(merged.invoices,  0,  "max(0, 0) = 0")
    }

    func test_merged_allIsRecomputed() {
        let local = SearchScopeCounts(
            all: 0, customers: 0, tickets: 0,
            inventory: 0, invoices: 0, notes: 2
        )
        let fts = ScopeCounts(
            customers: 1, tickets: 1
        )
        let merged = local.merged(with: fts)
        // customers(1) + tickets(1) + inventory(0) + invoices(0) + notes(2) = 5
        XCTAssertEqual(merged.all, 5)
    }

    // MARK: - Equatable

    func test_equatable_sameValuesAreEqual() {
        let a = SearchScopeCounts(all: 5, customers: 2, tickets: 1,
                                  inventory: 1, invoices: 1, notes: 0)
        let b = SearchScopeCounts(all: 5, customers: 2, tickets: 1,
                                  inventory: 1, invoices: 1, notes: 0)
        XCTAssertEqual(a, b)
    }

    func test_equatable_differentValuesAreNotEqual() {
        let a = SearchScopeCounts(customers: 2)
        let b = SearchScopeCounts(customers: 3)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Helpers

    private func makeHit(entity: String, id: String, title: String = "Test") -> SearchHit {
        SearchHit(entity: entity, entityId: id, title: title, snippet: "", score: 0)
    }
}
