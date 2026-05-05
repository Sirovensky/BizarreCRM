import XCTest
@testable import Reports

// MARK: - InventoryReportTests
// Tests for InventoryReport, InventoryReportResponse decoding,
// InventoryTurnoverRow decoding from both server and legacy shapes.

final class InventoryReportTests: XCTestCase {

    // MARK: - InventoryReportResponse decoding

    func test_inventoryReportResponse_decodesOutOfStock() throws {
        let json = """
        {
            "lowStock": [],
            "valueSummary": [],
            "outOfStock": 5,
            "topMoving": [
                {"name": "Widget A", "sku": "WA1", "used_qty": 25, "in_stock": 100}
            ]
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(InventoryReportResponse.self, from: json)
        XCTAssertEqual(decoded.outOfStock, 5)
        XCTAssertEqual(decoded.topMoving.count, 1)
        XCTAssertEqual(decoded.topMoving[0].name, "Widget A")
        XCTAssertEqual(decoded.topMoving[0].usedQty, 25)
        XCTAssertEqual(decoded.topMoving[0].inStock, 100)
    }

    func test_inventoryReportResponse_emptyData_defaults() throws {
        let json = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(InventoryReportResponse.self, from: json)
        XCTAssertEqual(decoded.outOfStock, 0)
        XCTAssertTrue(decoded.topMoving.isEmpty)
        XCTAssertTrue(decoded.lowStock.isEmpty)
    }

    func test_inventoryValueEntry_decodes() throws {
        let json = """
        {
            "item_type": "part",
            "item_count": 10,
            "total_units": 200,
            "total_cost_value": 5000.0,
            "total_retail_value": 8000.0
        }
        """.data(using: .utf8)!
        let entry = try JSONDecoder().decode(InventoryValueEntry.self, from: json)
        XCTAssertEqual(entry.itemType, "part")
        XCTAssertEqual(entry.itemCount, 10)
        XCTAssertEqual(entry.totalCostValue, 5000.0, accuracy: 0.001)
        XCTAssertEqual(entry.totalRetailValue, 8000.0, accuracy: 0.001)
        XCTAssertEqual(entry.id, "part")
    }

    // MARK: - InventoryTurnoverRow decoding

    func test_inventoryTurnoverRow_decodesServerCategoryShape() throws {
        let json = """
        {
            "category": "Accessories",
            "sold_units": 150,
            "sold_value": 3000.0,
            "avg_stock_value": 1500.0,
            "turns_90d": 2.0,
            "status": "healthy"
        }
        """.data(using: .utf8)!
        let row = try JSONDecoder().decode(InventoryTurnoverRow.self, from: json)
        XCTAssertEqual(row.name, "Accessories")
        XCTAssertEqual(row.sku, "Accessories")
        XCTAssertEqual(row.turnoverRate, 2.0, accuracy: 0.001)
        // daysOnHand = 90 / turns = 45
        XCTAssertEqual(row.daysOnHand, 45.0, accuracy: 0.001)
        XCTAssertEqual(row.status, "healthy")
    }

    func test_inventoryTurnoverRow_decodesLegacyShape() throws {
        let json = """
        {"id": 3, "sku": "SKU01", "name": "Charger", "turnover_rate": 1.5, "days_on_hand": 60.0}
        """.data(using: .utf8)!
        let row = try JSONDecoder().decode(InventoryTurnoverRow.self, from: json)
        XCTAssertEqual(row.id, 3)
        XCTAssertEqual(row.sku, "SKU01")
        XCTAssertEqual(row.name, "Charger")
        XCTAssertEqual(row.turnoverRate, 1.5, accuracy: 0.001)
        XCTAssertEqual(row.daysOnHand, 60.0, accuracy: 0.001)
        XCTAssertNil(row.status)
    }

    func test_inventoryTurnoverRow_zeroTurns_givesBigDaysOnHand() throws {
        let json = """
        {"category": "Orphan", "turns_90d": 0.0, "status": "stagnant"}
        """.data(using: .utf8)!
        let row = try JSONDecoder().decode(InventoryTurnoverRow.self, from: json)
        // Should not divide by zero
        XCTAssertGreaterThan(row.daysOnHand, 1000)
    }

    // MARK: - InventoryMovementItem

    func test_inventoryMovementItem_decodes() throws {
        let json = """
        {"name": "Screen Protector", "sku": "SP01", "used_qty": 42, "in_stock": 200}
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(InventoryMovementItem.self, from: json)
        XCTAssertEqual(item.name, "Screen Protector")
        XCTAssertEqual(item.sku, "SP01")
        XCTAssertEqual(item.usedQty, 42)
        XCTAssertEqual(item.inStock, 200)
        XCTAssertEqual(item.id, "Screen Protector")
    }

    func test_inventoryMovementItem_nullSku_isNil() throws {
        let json = """
        {"name": "Unknown", "used_qty": 1, "in_stock": 0}
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(InventoryMovementItem.self, from: json)
        XCTAssertNil(item.sku)
    }

    // MARK: - InventoryReport assembly

    func test_inventoryReport_lowStockCount_matchesLowStockArray() {
        let lowStock = [
            InventoryMovementItem.fixture(name: "A"),
            InventoryMovementItem.fixture(name: "B")
        ]
        let report = InventoryReport(
            outOfStockCount: 2,
            lowStockCount: lowStock.count,
            valueSummary: [],
            topMoving: []
        )
        XCTAssertEqual(report.lowStockCount, 2)
        XCTAssertEqual(report.outOfStockCount, 2)
    }
}
