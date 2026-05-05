import XCTest
@testable import Inventory

// MARK: - InventoryKitTests
//
// Tests for the InventoryKit and InventoryKitComponent value types:
// derived properties, cost/retail calculations, and Decodable conformance.

final class InventoryKitTests: XCTestCase {

    // MARK: - InventoryKitComponent derived properties

    func test_component_isStockInsufficient_falseWhenStockMeetsQty() {
        let comp = InventoryKitComponent(
            id: 1, kitId: 10, inventoryItemId: 100,
            quantity: 5, inStock: 5
        )
        XCTAssertEqual(comp.isStockInsufficient, false)
    }

    func test_component_isStockInsufficient_trueWhenStockBelowQty() {
        let comp = InventoryKitComponent(
            id: 2, kitId: 10, inventoryItemId: 101,
            quantity: 3, inStock: 2
        )
        XCTAssertEqual(comp.isStockInsufficient, true)
    }

    func test_component_isStockInsufficient_nilWhenNoStockData() {
        let comp = InventoryKitComponent(
            id: 3, kitId: 10, inventoryItemId: 102,
            quantity: 1
        )
        XCTAssertNil(comp.isStockInsufficient)
    }

    func test_component_extendedCostCents_multipliesCorrectly() {
        let comp = InventoryKitComponent(
            id: 4, kitId: 10, inventoryItemId: 103,
            quantity: 3, costPriceCents: 1000
        )
        XCTAssertEqual(comp.extendedCostCents, 3000)
    }

    func test_component_extendedCostCents_nilWhenNoCostData() {
        let comp = InventoryKitComponent(
            id: 5, kitId: 10, inventoryItemId: 104,
            quantity: 2
        )
        XCTAssertNil(comp.extendedCostCents)
    }

    func test_component_extendedRetailCents_multipliesCorrectly() {
        let comp = InventoryKitComponent(
            id: 6, kitId: 10, inventoryItemId: 105,
            quantity: 2, retailPriceCents: 2500
        )
        XCTAssertEqual(comp.extendedRetailCents, 5000)
    }

    // MARK: - InventoryKit totalCostCents

    func test_kit_totalCostCents_sumsAllComponentCosts() {
        let kit = InventoryKit(
            id: 1, name: "Screen Kit",
            items: [
                InventoryKitComponent(id: 1, kitId: 1, inventoryItemId: 10, quantity: 2, costPriceCents: 500),
                InventoryKitComponent(id: 2, kitId: 1, inventoryItemId: 11, quantity: 1, costPriceCents: 1200),
            ]
        )
        // 2*500 + 1*1200 = 2200
        XCTAssertEqual(kit.totalCostCents, 2200)
    }

    func test_kit_totalCostCents_nilWhenNoItemsHaveCost() {
        let kit = InventoryKit(
            id: 2, name: "No Cost Kit",
            items: [
                InventoryKitComponent(id: 3, kitId: 2, inventoryItemId: 20, quantity: 1),
            ]
        )
        XCTAssertNil(kit.totalCostCents)
    }

    func test_kit_totalCostCents_nilWhenItemsArrayIsNil() {
        let kit = InventoryKit(id: 3, name: "List-only Kit")
        XCTAssertNil(kit.totalCostCents)
    }

    func test_kit_totalRetailCents_sumsAllComponentRetails() {
        let kit = InventoryKit(
            id: 4, name: "Retail Kit",
            items: [
                InventoryKitComponent(id: 4, kitId: 4, inventoryItemId: 30, quantity: 3, retailPriceCents: 1000),
                InventoryKitComponent(id: 5, kitId: 4, inventoryItemId: 31, quantity: 1, retailPriceCents: 4000),
            ]
        )
        // 3*1000 + 1*4000 = 7000
        XCTAssertEqual(kit.totalRetailCents, 7000)
    }

    // MARK: - Decodable

    func test_inventoryKit_decodesFromServerJSON() throws {
        let json = """
        {
            "id": 42,
            "name": "Starter Kit",
            "description": "Basic starter bundle",
            "item_count": 3,
            "created_at": "2025-01-15T10:00:00Z"
        }
        """.data(using: .utf8)!

        let kit = try JSONDecoder().decode(InventoryKit.self, from: json)
        XCTAssertEqual(kit.id, 42)
        XCTAssertEqual(kit.name, "Starter Kit")
        XCTAssertEqual(kit.description, "Basic starter bundle")
        XCTAssertEqual(kit.itemCount, 3)
        XCTAssertNil(kit.items) // list endpoint doesn't include items
    }

    func test_inventoryKitComponent_decodesFromServerJSON() throws {
        let json = """
        {
            "id": 7,
            "kit_id": 42,
            "inventory_item_id": 99,
            "quantity": 2,
            "item_name": "Screen Glass",
            "sku": "GLASS-001",
            "retail_price": 2999,
            "cost_price": 1500,
            "in_stock": 10
        }
        """.data(using: .utf8)!

        let comp = try JSONDecoder().decode(InventoryKitComponent.self, from: json)
        XCTAssertEqual(comp.id, 7)
        XCTAssertEqual(comp.kitId, 42)
        XCTAssertEqual(comp.inventoryItemId, 99)
        XCTAssertEqual(comp.quantity, 2)
        XCTAssertEqual(comp.itemName, "Screen Glass")
        XCTAssertEqual(comp.sku, "GLASS-001")
        XCTAssertEqual(comp.retailPriceCents, 2999)
        XCTAssertEqual(comp.costPriceCents, 1500)
        XCTAssertEqual(comp.inStock, 10)
        XCTAssertEqual(comp.extendedCostCents, 3000)   // 2 * 1500
        XCTAssertEqual(comp.extendedRetailCents, 5998)  // 2 * 2999
    }

    func test_inventoryKit_detailDecodesWithItems() throws {
        let json = """
        {
            "id": 5,
            "name": "Tool Bundle",
            "items": [
                {
                    "id": 1, "kit_id": 5, "inventory_item_id": 10,
                    "quantity": 1, "item_name": "Wrench", "sku": "TOOL-W",
                    "retail_price": 1000, "cost_price": 500, "in_stock": 20
                }
            ]
        }
        """.data(using: .utf8)!

        let kit = try JSONDecoder().decode(InventoryKit.self, from: json)
        XCTAssertEqual(kit.id, 5)
        XCTAssertEqual(kit.items?.count, 1)
        XCTAssertEqual(kit.totalCostCents, 500)
        XCTAssertEqual(kit.totalRetailCents, 1000)
    }
}
