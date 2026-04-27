import XCTest
@testable import Inventory
import Networking

final class ABCClassifierTests: XCTestCase {

    // MARK: - Helpers

    private func makeItem(id: Int64, name: String = "Item") -> InventoryListItem {
        InventoryListItem(
            id: id, sku: "SKU\(id)", displayName: name,
            itemType: .product, inStock: 10, reorderLevel: nil
        )
    }

    // MARK: - Classification tests

    func test_classify_noRevenue_allClassC() {
        let items = [makeItem(id: 1), makeItem(id: 2), makeItem(id: 3)]
        let revenues: [Int64: Int] = [:]
        let result = ABCClassifier.classify(items: items, revenues: revenues)
        XCTAssertTrue(result.allSatisfy { $0.abcClass == .c })
    }

    func test_classify_singleItem_classA() {
        let item = makeItem(id: 1)
        let revenues: [Int64: Int] = [1: 10000]
        let result = ABCClassifier.classify(items: [item], revenues: revenues)
        XCTAssertEqual(result.first?.abcClass, .a)
    }

    func test_classify_topItemsA_bottomC() {
        // Create 10 items where item 1 generates 80% of revenue
        let items = (1...10).map { makeItem(id: Int64($0)) }
        var revenues: [Int64: Int] = [:]
        revenues[1] = 8000   // 80%
        revenues[2] = 500    // 5% each for items 2-4 = 15%
        revenues[3] = 500
        revenues[4] = 500
        // Items 5-10 generate remaining 5%
        for i in 5...10 { revenues[Int64(i)] = 83 }

        let result = ABCClassifier.classify(items: items, revenues: revenues)
        let aCount = result.filter { $0.abcClass == .a }.count
        let cCount = result.filter { $0.abcClass == .c }.count

        XCTAssertGreaterThanOrEqual(aCount, 1)
        XCTAssertGreaterThanOrEqual(cCount, 1)
    }

    func test_classify_sortedByRevenue_descending() {
        let items = [makeItem(id: 1), makeItem(id: 2), makeItem(id: 3)]
        let revenues: [Int64: Int] = [1: 100, 2: 500, 3: 300]
        let result = ABCClassifier.classify(items: items, revenues: revenues)
        // First item should be the highest revenue (id 2)
        XCTAssertEqual(result.first?.id, 2)
    }

    func test_classify_zeroRevenueItems_classedAsC() {
        let items = [makeItem(id: 1), makeItem(id: 2)]
        let revenues: [Int64: Int] = [1: 1000]  // id 2 has no revenue
        let result = ABCClassifier.classify(items: items, revenues: revenues)
        let item2 = result.first { $0.id == 2 }
        XCTAssertEqual(item2?.abcClass, .c)
    }

    // MARK: - Group counts

    func test_groupCounts_returnsAllThreeClasses() {
        let items = ABCClass.allCases.enumerated().map { idx, cls in
            ABCItem(id: Int64(idx), sku: "S\(idx)", name: "Item \(idx)",
                    revenueCents: 100, abcClass: cls)
        }
        let counts = ABCClassifier.groupCounts(from: items)
        XCTAssertEqual(counts.count, 3)
        XCTAssertTrue(counts.allSatisfy { $0.1 == 1 })
    }

    func test_groupCounts_emptyItems_allZeroCounts() {
        let counts = ABCClassifier.groupCounts(from: [])
        XCTAssertEqual(counts.count, 3)
        XCTAssertTrue(counts.allSatisfy { $0.1 == 0 })
    }

    // MARK: - Revenue formatted

    func test_agedItem_revenueFormatted_dollarsAndCents() {
        let item = ABCItem(id: 1, sku: "A", name: "X", revenueCents: 1234, abcClass: .a)
        XCTAssertEqual(item.revenueFormatted, "$12")
    }
}
