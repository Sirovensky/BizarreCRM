import XCTest
@testable import Inventory

final class BundleUnpackerTests: XCTestCase {

    // MARK: - unpack: basic

    func test_unpack_singleComponent_qty1() {
        let bundle = makeBundle(components: [BundleComponent(componentSKU: "SCREEN-A", qty: 1)])
        let result = BundleUnpacker.unpack(bundle: bundle, quantity: 1)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].sku, "SCREEN-A")
        XCTAssertEqual(result[0].qty, 1)
    }

    func test_unpack_singleComponent_quantity3_multiplies() {
        let bundle = makeBundle(components: [BundleComponent(componentSKU: "BATT-01", qty: 2)])
        let result = BundleUnpacker.unpack(bundle: bundle, quantity: 3)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].sku, "BATT-01")
        XCTAssertEqual(result[0].qty, 6)  // 2 × 3
    }

    func test_unpack_multipleComponents_allDecremented() {
        let bundle = makeBundle(components: [
            BundleComponent(componentSKU: "SCREEN", qty: 1),
            BundleComponent(componentSKU: "BATTERY", qty: 1),
            BundleComponent(componentSKU: "ADHESIVE", qty: 2)
        ])
        let result = BundleUnpacker.unpack(bundle: bundle, quantity: 1)
        XCTAssertEqual(result.count, 3)
        let skus = result.map(\.sku)
        XCTAssertTrue(skus.contains("SCREEN"))
        XCTAssertTrue(skus.contains("BATTERY"))
        XCTAssertTrue(skus.contains("ADHESIVE"))
    }

    func test_unpack_multiComponent_quantity2_correctTotals() {
        let bundle = makeBundle(components: [
            BundleComponent(componentSKU: "PART-A", qty: 3),
            BundleComponent(componentSKU: "PART-B", qty: 1)
        ])
        let result = BundleUnpacker.unpack(bundle: bundle, quantity: 2)
        let a = result.first(where: { $0.sku == "PART-A" })
        let b = result.first(where: { $0.sku == "PART-B" })
        XCTAssertEqual(a?.qty, 6)  // 3 × 2
        XCTAssertEqual(b?.qty, 2)  // 1 × 2
    }

    func test_unpack_emptyComponents_returnsEmpty() {
        let bundle = makeBundle(components: [])
        let result = BundleUnpacker.unpack(bundle: bundle, quantity: 5)
        XCTAssertTrue(result.isEmpty)
    }

    func test_unpack_zeroQuantity_returnsEmpty() {
        let bundle = makeBundle(components: [BundleComponent(componentSKU: "SCREEN", qty: 1)])
        let result = BundleUnpacker.unpack(bundle: bundle, quantity: 0)
        XCTAssertTrue(result.isEmpty)
    }

    func test_unpack_negativeQuantity_returnsEmpty() {
        let bundle = makeBundle(components: [BundleComponent(componentSKU: "SCREEN", qty: 1)])
        let result = BundleUnpacker.unpack(bundle: bundle, quantity: -1)
        XCTAssertTrue(result.isEmpty)
    }

    func test_unpack_emptySKU_componentIsSkipped() {
        let bundle = makeBundle(components: [
            BundleComponent(componentSKU: "", qty: 1),
            BundleComponent(componentSKU: "VALID-SKU", qty: 1)
        ])
        let result = BundleUnpacker.unpack(bundle: bundle, quantity: 1)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].sku, "VALID-SKU")
    }

    // MARK: - validate

    func test_validate_valid_noWarnings() {
        let bundle = makeBundle(components: [
            BundleComponent(componentSKU: "PART-A", qty: 1),
            BundleComponent(componentSKU: "PART-B", qty: 2)
        ])
        XCTAssertTrue(BundleUnpacker.validate(bundle: bundle).isEmpty)
    }

    func test_validate_emptySKU_warning() {
        let bundle = makeBundle(components: [BundleComponent(componentSKU: "", qty: 1)])
        let warnings = BundleUnpacker.validate(bundle: bundle)
        XCTAssertEqual(warnings.count, 1)
    }

    func test_validate_zeroQty_warning() {
        let bundle = makeBundle(components: [BundleComponent(componentSKU: "SKU-A", qty: 0)])
        let warnings = BundleUnpacker.validate(bundle: bundle)
        XCTAssertEqual(warnings.count, 1)
    }

    func test_validate_multipleInvalid_allWarnings() {
        let bundle = makeBundle(components: [
            BundleComponent(componentSKU: "", qty: 1),
            BundleComponent(componentSKU: "SKU-B", qty: -1),
            BundleComponent(componentSKU: "SKU-C", qty: 1)  // valid
        ])
        let warnings = BundleUnpacker.validate(bundle: bundle)
        XCTAssertEqual(warnings.count, 2)
    }

    // MARK: - Helpers

    private func makeBundle(components: [BundleComponent]) -> InventoryBundle {
        InventoryBundle(
            id: 1,
            sku: "KIT-001",
            name: "Test Bundle",
            components: components,
            bundlePriceCents: 14999,
            individualPriceSum: 19999
        )
    }
}
