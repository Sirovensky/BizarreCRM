import XCTest
@testable import Inventory

final class VariantStockAggregatorTests: XCTestCase {

    // MARK: - totalStock

    func test_totalStock_empty_returnsZero() {
        XCTAssertEqual(VariantStockAggregator.totalStock(variants: []), 0)
    }

    func test_totalStock_singleVariant() {
        let v = makeVariant(id: 1, stock: 10)
        XCTAssertEqual(VariantStockAggregator.totalStock(variants: [v]), 10)
    }

    func test_totalStock_multipleVariants_sumsAll() {
        let variants = [
            makeVariant(id: 1, stock: 5),
            makeVariant(id: 2, stock: 3),
            makeVariant(id: 3, stock: 12)
        ]
        XCTAssertEqual(VariantStockAggregator.totalStock(variants: variants), 20)
    }

    func test_totalStock_zeroStock_variants() {
        let variants = [
            makeVariant(id: 1, stock: 0),
            makeVariant(id: 2, stock: 0)
        ]
        XCTAssertEqual(VariantStockAggregator.totalStock(variants: variants), 0)
    }

    // MARK: - isAnyInStock

    func test_isAnyInStock_empty_returnsFalse() {
        XCTAssertFalse(VariantStockAggregator.isAnyInStock(variants: []))
    }

    func test_isAnyInStock_allZero_returnsFalse() {
        let variants = [makeVariant(id: 1, stock: 0), makeVariant(id: 2, stock: 0)]
        XCTAssertFalse(VariantStockAggregator.isAnyInStock(variants: variants))
    }

    func test_isAnyInStock_onePositive_returnsTrue() {
        let variants = [makeVariant(id: 1, stock: 0), makeVariant(id: 2, stock: 1)]
        XCTAssertTrue(VariantStockAggregator.isAnyInStock(variants: variants))
    }

    // MARK: - grouped

    func test_grouped_byColor_correctKeys() {
        let variants = [
            makeVariant(id: 1, attributes: ["color": "Red", "size": "S"]),
            makeVariant(id: 2, attributes: ["color": "Blue", "size": "M"]),
            makeVariant(id: 3, attributes: ["color": "Red", "size": "L"])
        ]
        let grouped = VariantStockAggregator.grouped(variants: variants, byAttribute: "color")
        XCTAssertEqual(grouped.keys.count, 2)
        XCTAssertEqual(grouped["Red"]?.count, 2)
        XCTAssertEqual(grouped["Blue"]?.count, 1)
    }

    func test_grouped_missingAttribute_usesUnknown() {
        let variants = [makeVariant(id: 1, attributes: ["size": "S"])]
        let grouped = VariantStockAggregator.grouped(variants: variants, byAttribute: "color")
        XCTAssertNotNil(grouped["Unknown"])
    }

    // MARK: - distinctValues

    func test_distinctValues_sorted() {
        let variants = [
            makeVariant(id: 1, attributes: ["size": "XL"]),
            makeVariant(id: 2, attributes: ["size": "S"]),
            makeVariant(id: 3, attributes: ["size": "M"]),
            makeVariant(id: 4, attributes: ["size": "S"])  // duplicate
        ]
        let values = VariantStockAggregator.distinctValues(variants: variants, forAttribute: "size")
        XCTAssertEqual(values, ["M", "S", "XL"])
    }

    func test_distinctValues_noKey_empty() {
        let variants = [makeVariant(id: 1, attributes: ["color": "Red"])]
        let values = VariantStockAggregator.distinctValues(variants: variants, forAttribute: "size")
        XCTAssertTrue(values.isEmpty)
    }

    // MARK: - Helpers

    private func makeVariant(
        id: Int64,
        attributes: [String: String] = ["color": "Red"],
        stock: Int = 0
    ) -> InventoryVariant {
        InventoryVariant(
            id: id,
            parentSKU: "PARENT-001",
            attributes: attributes,
            sku: "PARENT-001-\(id)",
            stock: stock,
            retailCents: 9999,
            costCents: 5000
        )
    }
}
