import XCTest
@testable import Inventory
import Networking

final class ReorderSuggestionEngineTests: XCTestCase {

    private let defaultPolicy = ReorderPolicy(leadTimeDays: 7, safetyStock: 5, minOrderQty: 1)

    // MARK: - No reorder needed

    func test_suggestions_aboveReorderLevel_noSuggestions() {
        let items = [
            makeItem(id: 1, inStock: 20, reorderLevel: 10)
        ]
        let result = ReorderSuggestionEngine.suggestions(items: items, policy: defaultPolicy)
        XCTAssertTrue(result.isEmpty)
    }

    func test_suggestions_exactlyAtReorderLevel_isSuggested() {
        let items = [makeItem(id: 1, inStock: 10, reorderLevel: 10)]
        let result = ReorderSuggestionEngine.suggestions(items: items, policy: defaultPolicy)
        XCTAssertEqual(result.count, 1)
    }

    func test_suggestions_belowReorderLevel_isSuggested() {
        let items = [makeItem(id: 1, inStock: 3, reorderLevel: 10)]
        let result = ReorderSuggestionEngine.suggestions(items: items, policy: defaultPolicy)
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - Suggested quantities

    func test_suggestion_qty_reachesTargetStock() {
        // target = reorderLevel(10) + safetyStock(5) = 15
        // current = 3 → suggest 12 (15 - 3)
        let item = makeItem(id: 1, inStock: 3, reorderLevel: 10)
        let s = ReorderSuggestionEngine.suggestion(for: item, policy: defaultPolicy)
        XCTAssertNotNil(s)
        XCTAssertEqual(s?.projectedStock, s!.suggestedQty + 3)
        XCTAssertGreaterThanOrEqual(s!.projectedStock, 15)
    }

    func test_suggestion_minOrderQtyEnforced() {
        let policy = ReorderPolicy(leadTimeDays: 3, safetyStock: 0, minOrderQty: 10)
        let item = makeItem(id: 1, inStock: 9, reorderLevel: 10)  // raw shortage = 1
        let s = ReorderSuggestionEngine.suggestion(for: item, policy: policy)
        XCTAssertNotNil(s)
        XCTAssertGreaterThanOrEqual(s!.suggestedQty, 10)
    }

    func test_suggestion_minOrderQty_roundsUpToMultiple() {
        let policy = ReorderPolicy(leadTimeDays: 7, safetyStock: 2, minOrderQty: 5)
        // inStock=8, reorderLevel=10, target=12, raw=4 → round up to 5
        let item = makeItem(id: 1, inStock: 8, reorderLevel: 10)
        let s = ReorderSuggestionEngine.suggestion(for: item, policy: policy)
        XCTAssertEqual(s?.suggestedQty, 5)
    }

    // MARK: - Multiple items sorting

    func test_suggestions_sortedByUrgency_mostUrgentFirst() {
        let items = [
            makeItem(id: 1, inStock: 8, reorderLevel: 10),   // shortage 2
            makeItem(id: 2, inStock: 1, reorderLevel: 10),   // shortage 9 ← most urgent
            makeItem(id: 3, inStock: 5, reorderLevel: 10)    // shortage 5
        ]
        let result = ReorderSuggestionEngine.suggestions(items: items, policy: defaultPolicy)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].item.id, 2)  // most urgent
        XCTAssertEqual(result[1].item.id, 3)
        XCTAssertEqual(result[2].item.id, 1)
    }

    func test_suggestions_mixedStock_onlyBelowThreshold() {
        let items = [
            makeItem(id: 1, inStock: 50, reorderLevel: 10),  // fine
            makeItem(id: 2, inStock: 2,  reorderLevel: 10),  // needs reorder
            makeItem(id: 3, inStock: 0,  reorderLevel: 0),   // reorderLevel=0 → skip
            makeItem(id: 4, inStock: 5,  reorderLevel: 10)   // needs reorder
        ]
        let result = ReorderSuggestionEngine.suggestions(items: items, policy: defaultPolicy)
        XCTAssertEqual(result.count, 2)
    }

    // MARK: - Nil / missing fields

    func test_suggestion_nilInStock_skipped() {
        let item = makeItem(id: 1, inStock: nil, reorderLevel: 10)
        XCTAssertNil(ReorderSuggestionEngine.suggestion(for: item, policy: defaultPolicy))
    }

    func test_suggestion_nilReorderLevel_skipped() {
        let item = makeItem(id: 1, inStock: 3, reorderLevel: nil)
        XCTAssertNil(ReorderSuggestionEngine.suggestion(for: item, policy: defaultPolicy))
    }

    func test_suggestion_zeroReorderLevel_skipped() {
        let item = makeItem(id: 1, inStock: 0, reorderLevel: 0)
        XCTAssertNil(ReorderSuggestionEngine.suggestion(for: item, policy: defaultPolicy))
    }

    // MARK: - Helpers

    private func makeItem(id: Int64, inStock: Int?, reorderLevel: Int?) -> InventoryListItem {
        InventoryListItemBuilder(
            id: id,
            inStock: inStock,
            reorderLevel: reorderLevel
        ).build()
    }
}

// MARK: - Builder helper (keeps Decodable init hidden)

private struct InventoryListItemBuilder {
    let id: Int64
    let inStock: Int?
    let reorderLevel: Int?

    func build() -> InventoryListItem {
        let json: [String: Any?] = [
            "id": id,
            "name": "Test Item \(id)",
            "sku": "SKU-\(id)",
            "in_stock": inStock as Any,
            "reorder_level": reorderLevel as Any
        ]
        let data = try! JSONSerialization.data(withJSONObject: json.compactMapValues { $0 })
        return try! JSONDecoder().decode(InventoryListItem.self, from: data)
    }
}
