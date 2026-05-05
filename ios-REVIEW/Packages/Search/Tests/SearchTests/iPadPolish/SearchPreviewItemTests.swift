import XCTest
@testable import Search

/// §22 — Unit tests for `SearchPreviewItem`.
final class SearchPreviewItemTests: XCTestCase {

    // MARK: - id derivation

    func test_id_isEntityColonEntityId() {
        let item = SearchPreviewItem(entity: "tickets", entityId: "T-42", title: "Screen crack")
        XCTAssertEqual(item.id, "tickets:T-42")
    }

    func test_id_uniquePerEntityAndId() {
        let a = SearchPreviewItem(entity: "tickets",   entityId: "1", title: "A")
        let b = SearchPreviewItem(entity: "customers", entityId: "1", title: "B")
        XCTAssertNotEqual(a.id, b.id)
    }

    // MARK: - from(hit:)

    func test_fromHit_mapsFieldsCorrectly() {
        let hit = SearchHit(
            entity: "invoices",
            entityId: "INV-99",
            title: "Invoice for Alice",
            snippet: "partial match here",
            score: -1.5
        )
        let item = SearchPreviewItem.from(hit: hit)

        XCTAssertEqual(item.entity,   "invoices")
        XCTAssertEqual(item.entityId, "INV-99")
        XCTAssertEqual(item.title,    "Invoice for Alice")
        XCTAssertEqual(item.snippet,  "partial match here")
        XCTAssertNil(item.subtitle)
    }

    func test_fromHit_emptySnippetBecomesNil() {
        let hit = SearchHit(entity: "customers", entityId: "C-1", title: "Bob", snippet: "", score: 0)
        let item = SearchPreviewItem.from(hit: hit)
        XCTAssertNil(item.snippet)
    }

    // MARK: - from(row:) — local case

    func test_fromRow_localHit_mapsFieldsCorrectly() {
        let hit = SearchHit(
            entity: "inventory",
            entityId: "SKU-77",
            title: "Widget Pro",
            snippet: "in <b>stock</b>",
            score: -0.9
        )
        let row = SearchResultMerger.MergedRow.local(hit)
        let item = SearchPreviewItem.from(row: row)

        XCTAssertEqual(item.entity,   "inventory")
        XCTAssertEqual(item.entityId, "SKU-77")
        XCTAssertEqual(item.title,    "Widget Pro")
        XCTAssertEqual(item.snippet,  "in <b>stock</b>")
    }

    // MARK: - Hashable / Equatable

    func test_hashable_sameItemsHaveSameHash() {
        let a = SearchPreviewItem(entity: "tickets", entityId: "1", title: "X")
        let b = SearchPreviewItem(entity: "tickets", entityId: "1", title: "X")
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func test_equatable_sameItemsAreEqual() {
        let a = SearchPreviewItem(entity: "tickets", entityId: "1", title: "X")
        let b = SearchPreviewItem(entity: "tickets", entityId: "1", title: "X")
        XCTAssertEqual(a, b)
    }

    func test_equatable_differentEntityIdNotEqual() {
        let a = SearchPreviewItem(entity: "tickets", entityId: "1", title: "X")
        let b = SearchPreviewItem(entity: "tickets", entityId: "2", title: "X")
        XCTAssertNotEqual(a, b)
    }

    func test_equatable_differentEntityNotEqual() {
        let a = SearchPreviewItem(entity: "tickets",   entityId: "1", title: "X")
        let b = SearchPreviewItem(entity: "customers", entityId: "1", title: "X")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Optional fields

    func test_optionalFields_defaultNil() {
        let item = SearchPreviewItem(entity: "notes", entityId: "N-1", title: "Meeting notes")
        XCTAssertNil(item.snippet)
        XCTAssertNil(item.subtitle)
    }

    func test_optionalFields_preservedWhenSet() {
        let item = SearchPreviewItem(
            entity: "notes",
            entityId: "N-2",
            title: "Q1 Review",
            snippet: "quarterly",
            subtitle: "John Doe"
        )
        XCTAssertEqual(item.snippet,  "quarterly")
        XCTAssertEqual(item.subtitle, "John Doe")
    }

    // MARK: - Sendable (compile-time check via let)

    func test_isSendable_usableAcrossActors() async {
        let item = SearchPreviewItem(entity: "tickets", entityId: "T-1", title: "Test")
        // If SearchPreviewItem is not Sendable this Task block would fail to compile.
        let result = await Task.detached { item }.value
        XCTAssertEqual(result.id, item.id)
    }
}
