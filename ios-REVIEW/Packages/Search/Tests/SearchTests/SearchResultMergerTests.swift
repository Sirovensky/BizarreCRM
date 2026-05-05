import XCTest
@testable import Search

final class SearchResultMergerTests: XCTestCase {

    // MARK: - Helpers

    private func makeLocalHit(
        entity: String = "customers",
        entityId: String = "1",
        title: String = "Alice",
        snippet: String = "Alice <b>Smith</b>",
        score: Double = -1.0
    ) -> SearchHit {
        SearchHit(entity: entity, entityId: entityId, title: title, snippet: snippet, score: score)
    }

    private func makeRemoteRow(
        id: Int64 = 1,
        display: String = "Alice Smith",
        type: String = "customer",
        subtitle: String? = "555-0100"
    ) -> GlobalSearchResults.Row {
        GlobalSearchResults.Row(id: id, display: display, type: type, subtitle: subtitle)
    }

    private func makeRemoteResults(
        customers: [GlobalSearchResults.Row] = [],
        tickets: [GlobalSearchResults.Row] = [],
        inventory: [GlobalSearchResults.Row] = [],
        invoices: [GlobalSearchResults.Row] = []
    ) -> GlobalSearchResults {
        GlobalSearchResults(customers: customers, tickets: tickets, inventory: inventory, invoices: invoices)
    }

    // MARK: - No remote

    func test_merge_nilRemote_returnsLocalOnly() {
        let local = [makeLocalHit()]
        let rows = SearchResultMerger.merge(localHits: local, remote: nil, filter: .all)
        XCTAssertEqual(rows.count, 1)
        if case .local = rows[0] { } else {
            XCTFail("Expected a local row")
        }
    }

    func test_merge_nilRemote_emptyLocal_returnsEmpty() {
        let rows = SearchResultMerger.merge(localHits: [], remote: nil, filter: .all)
        XCTAssertTrue(rows.isEmpty)
    }

    // MARK: - No local

    func test_merge_emptyLocal_remoteOnly() {
        let remote = makeRemoteResults(
            customers: [makeRemoteRow(id: 10, display: "Bob", type: "customer")]
        )
        let rows = SearchResultMerger.merge(localHits: [], remote: remote, filter: .all)
        XCTAssertEqual(rows.count, 1)
        if case .remote = rows[0] { } else {
            XCTFail("Expected a remote row")
        }
    }

    // MARK: - Deduplication

    func test_merge_dedupes_localAndRemoteSameId() {
        let local = [makeLocalHit(entity: "customers", entityId: "1")]
        let remote = makeRemoteResults(
            customers: [makeRemoteRow(id: 1, display: "Alice", type: "customer")]
        )
        let rows = SearchResultMerger.merge(localHits: local, remote: remote, filter: .all)
        // Should only have 1 row — the local one.
        XCTAssertEqual(rows.count, 1)
        if case .local = rows[0] { } else {
            XCTFail("Local hit should win dedup over remote")
        }
    }

    func test_merge_noDedup_differentIds() {
        let local = [makeLocalHit(entity: "customers", entityId: "1")]
        let remote = makeRemoteResults(
            customers: [makeRemoteRow(id: 2, display: "Bob", type: "customer")]
        )
        let rows = SearchResultMerger.merge(localHits: local, remote: remote, filter: .all)
        XCTAssertEqual(rows.count, 2)
    }

    func test_merge_localAppearsFirst() {
        let local = [makeLocalHit(entity: "customers", entityId: "1")]
        let remote = makeRemoteResults(
            customers: [makeRemoteRow(id: 99, display: "Other", type: "customer")]
        )
        let rows = SearchResultMerger.merge(localHits: local, remote: remote, filter: .all)
        if case .local = rows[0] { } else {
            XCTFail("Local rows should appear before remote rows")
        }
    }

    // MARK: - Filter

    func test_merge_filterCustomers_excludesTickets() {
        let local = [
            makeLocalHit(entity: "customers", entityId: "1"),
            makeLocalHit(entity: "tickets",   entityId: "2")
        ]
        let remote = makeRemoteResults(
            tickets: [makeRemoteRow(id: 3, display: "T-3", type: "ticket")]
        )
        let rows = SearchResultMerger.merge(localHits: local, remote: remote, filter: .customers)
        XCTAssertTrue(rows.allSatisfy { $0.entity == "customers" }, "Only customer rows should pass")
    }

    func test_merge_filterAll_includesEverything() {
        let local = [
            makeLocalHit(entity: "customers", entityId: "1"),
            makeLocalHit(entity: "tickets",   entityId: "2")
        ]
        let remote = makeRemoteResults(
            inventory: [makeRemoteRow(id: 3, display: "Protector", type: "inventory")]
        )
        let rows = SearchResultMerger.merge(localHits: local, remote: remote, filter: .all)
        XCTAssertEqual(rows.count, 3)
    }

    func test_merge_filterTickets_excludesLocalCustomers() {
        let local = [
            makeLocalHit(entity: "customers", entityId: "1"),
            makeLocalHit(entity: "tickets",   entityId: "2")
        ]
        let rows = SearchResultMerger.merge(localHits: local, remote: nil, filter: .tickets)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.entity, "tickets")
    }

    // MARK: - MergedRow properties

    func test_mergedRow_local_titleIsHitTitle() {
        let hit = makeLocalHit(title: "My Title")
        let row = SearchResultMerger.MergedRow.local(hit)
        XCTAssertEqual(row.title, "My Title")
    }

    func test_mergedRow_remote_titleIsDisplayField() {
        let row = GlobalSearchResults.Row(id: 1, display: "Remote Title", type: "customer", subtitle: nil)
        let merged = SearchResultMerger.MergedRow.remote(row, entity: "customers")
        XCTAssertEqual(merged.title, "Remote Title")
    }

    func test_mergedRow_local_snippetAvailable() {
        let hit = makeLocalHit(snippet: "matched <b>term</b>")
        let merged = SearchResultMerger.MergedRow.local(hit)
        XCTAssertNotNil(merged.snippet)
    }

    func test_mergedRow_remote_snippetNil() {
        let row = makeRemoteRow()
        let merged = SearchResultMerger.MergedRow.remote(row, entity: "customers")
        XCTAssertNil(merged.snippet)
    }

    func test_mergedRow_id_isUnique() {
        let local = SearchResultMerger.MergedRow.local(makeLocalHit(entity: "customers", entityId: "1"))
        let remote = SearchResultMerger.MergedRow.remote(makeRemoteRow(id: 1), entity: "customers")
        XCTAssertNotEqual(local.id, remote.id, "Local and remote IDs must be unique even with same entity+entityId")
    }

    // MARK: - All remote entity types

    func test_merge_allFourRemoteEntities_included() {
        let remote = makeRemoteResults(
            customers:  [makeRemoteRow(id: 1, type: "customer")],
            tickets:    [makeRemoteRow(id: 2, type: "ticket")],
            inventory:  [makeRemoteRow(id: 3, type: "inventory")],
            invoices:   [makeRemoteRow(id: 4, type: "invoice")]
        )
        let rows = SearchResultMerger.merge(localHits: [], remote: remote, filter: .all)
        XCTAssertEqual(rows.count, 4)
    }
}
