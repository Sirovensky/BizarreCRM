import XCTest
@testable import Networking

/// §43 — Tests for `RepairPricingLookupResult` + `RepairPricingGrade`
/// + `RepairPricingAdjustments` JSON decoding.
///
/// All fixtures mirror the exact server snake_case response from
/// `GET /api/v1/repair-pricing/lookup`.
final class RepairPricingLookupTests: XCTestCase {

    // MARK: - Helpers

    private let decoder = JSONDecoder()

    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try decoder.decode(type, from: Data(json.utf8))
    }

    // MARK: - RepairPricingAdjustments

    func test_adjustments_decodesZero() throws {
        let adj = try decode(RepairPricingAdjustments.self, from: #"{"flat":0,"pct":0}"#)
        XCTAssertEqual(adj.flat, 0)
        XCTAssertEqual(adj.pct, 0)
    }

    func test_adjustments_decodesPositiveValues() throws {
        let adj = try decode(RepairPricingAdjustments.self, from: #"{"flat":5.50,"pct":10}"#)
        XCTAssertEqual(adj.flat, 5.50, accuracy: 0.001)
        XCTAssertEqual(adj.pct, 10, accuracy: 0.001)
    }

    func test_adjustments_decodesNegativeValues() throws {
        let adj = try decode(RepairPricingAdjustments.self, from: #"{"flat":-2.0,"pct":-5}"#)
        XCTAssertEqual(adj.flat, -2.0, accuracy: 0.001)
        XCTAssertEqual(adj.pct, -5, accuracy: 0.001)
    }

    func test_adjustments_equatable() {
        let a = RepairPricingAdjustments(flat: 5, pct: 10)
        let b = RepairPricingAdjustments(flat: 5, pct: 10)
        let c = RepairPricingAdjustments(flat: 0, pct: 0)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - RepairPricingGrade

    func test_grade_decodesRequiredFields() throws {
        let json = """
        {
          "id": 1,
          "grade": "aftermarket",
          "grade_label": "Aftermarket",
          "part_price": 4500,
          "effective_labor_price": 3000,
          "is_default": 1,
          "sort_order": 0
        }
        """
        let g = try decode(RepairPricingGrade.self, from: json)
        XCTAssertEqual(g.id, 1)
        XCTAssertEqual(g.grade, "aftermarket")
        XCTAssertEqual(g.gradeLabel, "Aftermarket")
        XCTAssertEqual(g.partPriceCents, 4500)
        XCTAssertEqual(g.effectiveLaborPriceCents, 3000)
        XCTAssertNil(g.laborPriceOverrideCents)
        XCTAssertEqual(g.isDefault, 1)
    }

    func test_grade_decodesOptionalFields() throws {
        let json = """
        {
          "id": 2,
          "grade": "oem",
          "grade_label": "OEM",
          "part_price": 8000,
          "labor_price_override": 2500,
          "effective_labor_price": 2500,
          "inventory_item_name": "OEM Screen",
          "inventory_in_stock": 5,
          "catalog_item_name": "Apple OEM Screen",
          "catalog_url": "https://supplier.example.com/screen",
          "is_default": 0,
          "sort_order": 1
        }
        """
        let g = try decode(RepairPricingGrade.self, from: json)
        XCTAssertEqual(g.laborPriceOverrideCents, 2500)
        XCTAssertEqual(g.inventoryItemName, "OEM Screen")
        XCTAssertEqual(g.inventoryInStock, 5)
        XCTAssertEqual(g.catalogItemName, "Apple OEM Screen")
        XCTAssertEqual(g.catalogUrl, "https://supplier.example.com/screen")
    }

    func test_grade_nullOptionalFields() throws {
        let json = """
        {
          "id": 3,
          "grade": "used",
          "grade_label": "Used",
          "part_price": 1500,
          "labor_price_override": null,
          "effective_labor_price": 3000,
          "inventory_item_name": null,
          "inventory_in_stock": null,
          "catalog_item_name": null,
          "catalog_url": null,
          "is_default": 0,
          "sort_order": 2
        }
        """
        let g = try decode(RepairPricingGrade.self, from: json)
        XCTAssertNil(g.laborPriceOverrideCents)
        XCTAssertNil(g.inventoryItemName)
        XCTAssertNil(g.inventoryInStock)
        XCTAssertNil(g.catalogItemName)
        XCTAssertNil(g.catalogUrl)
    }

    func test_grade_identifiableAndHashable() {
        let g1 = RepairPricingGrade(id: 1, grade: "aftermarket", gradeLabel: "Aftermarket")
        let g2 = RepairPricingGrade(id: 1, grade: "aftermarket", gradeLabel: "Aftermarket")
        let g3 = RepairPricingGrade(id: 2, grade: "oem", gradeLabel: "OEM")
        XCTAssertEqual(g1, g2)
        XCTAssertNotEqual(g1, g3)
        var set = Set<RepairPricingGrade>()
        set.insert(g1)
        set.insert(g2)
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - RepairPricingLookupResult

    func test_lookup_decodesFullResponse() throws {
        let json = """
        {
          "id": 42,
          "device_model_id": 7,
          "repair_service_id": 3,
          "device_model_name": "iPhone 15 Pro",
          "manufacturer_name": "Apple",
          "repair_service_name": "Screen Replacement",
          "repair_service_slug": "screen-replacement",
          "base_labor_price": 5000,
          "labor_price": 5500,
          "adjustments": { "flat": 5, "pct": 0 },
          "grades": [
            {
              "id": 1,
              "grade": "aftermarket",
              "grade_label": "Aftermarket",
              "part_price": 4000,
              "effective_labor_price": 5500,
              "is_default": 1,
              "sort_order": 0
            }
          ],
          "default_grade": "aftermarket",
          "is_active": 1
        }
        """
        let result = try decode(RepairPricingLookupResult.self, from: json)
        XCTAssertEqual(result.id, 42)
        XCTAssertEqual(result.deviceModelId, 7)
        XCTAssertEqual(result.repairServiceId, 3)
        XCTAssertEqual(result.deviceModelName, "iPhone 15 Pro")
        XCTAssertEqual(result.manufacturerName, "Apple")
        XCTAssertEqual(result.repairServiceName, "Screen Replacement")
        XCTAssertEqual(result.repairServiceSlug, "screen-replacement")
        XCTAssertEqual(result.baseLaborPriceCents, 5000)
        XCTAssertEqual(result.laborPriceCents, 5500)
        XCTAssertEqual(result.adjustments.flat, 5)
        XCTAssertEqual(result.adjustments.pct, 0)
        XCTAssertEqual(result.grades.count, 1)
        XCTAssertEqual(result.grades[0].grade, "aftermarket")
        XCTAssertEqual(result.defaultGrade, "aftermarket")
        XCTAssertEqual(result.isActive, 1)
    }

    func test_lookup_emptyGrades() throws {
        let json = """
        {
          "id": 1,
          "device_model_id": 1,
          "repair_service_id": 1,
          "device_model_name": "Pixel 8",
          "manufacturer_name": "Google",
          "repair_service_name": "Battery Swap",
          "repair_service_slug": "battery-swap",
          "base_labor_price": 2000,
          "labor_price": 2000,
          "adjustments": { "flat": 0, "pct": 0 },
          "grades": [],
          "default_grade": "aftermarket",
          "is_active": 1
        }
        """
        let result = try decode(RepairPricingLookupResult.self, from: json)
        XCTAssertTrue(result.grades.isEmpty)
        XCTAssertEqual(result.baseLaborPriceCents, 2000)
        XCTAssertEqual(result.laborPriceCents, 2000)
    }

    func test_lookup_multipleGrades() throws {
        let json = """
        {
          "id": 5,
          "device_model_id": 3,
          "repair_service_id": 2,
          "device_model_name": "Galaxy S24",
          "manufacturer_name": "Samsung",
          "repair_service_name": "Screen Replacement",
          "repair_service_slug": "screen-replacement",
          "base_labor_price": 6000,
          "labor_price": 6000,
          "adjustments": { "flat": 0, "pct": 0 },
          "grades": [
            {
              "id": 10,
              "grade": "aftermarket",
              "grade_label": "Aftermarket",
              "part_price": 3500,
              "effective_labor_price": 6000,
              "is_default": 1,
              "sort_order": 0
            },
            {
              "id": 11,
              "grade": "oem",
              "grade_label": "OEM",
              "part_price": 8000,
              "labor_price_override": 4000,
              "effective_labor_price": 4000,
              "is_default": 0,
              "sort_order": 1
            },
            {
              "id": 12,
              "grade": "used",
              "grade_label": "Used",
              "part_price": 1500,
              "effective_labor_price": 6000,
              "is_default": 0,
              "sort_order": 2
            }
          ],
          "default_grade": "aftermarket",
          "is_active": 1
        }
        """
        let result = try decode(RepairPricingLookupResult.self, from: json)
        XCTAssertEqual(result.grades.count, 3)
        XCTAssertEqual(result.grades[0].grade, "aftermarket")
        XCTAssertEqual(result.grades[1].grade, "oem")
        XCTAssertEqual(result.grades[1].laborPriceOverrideCents, 4000)
        XCTAssertEqual(result.grades[2].grade, "used")
    }

    func test_lookup_identifiableAndHashable() {
        let r1 = RepairPricingLookupResult(
            id: 1, deviceModelId: 1, repairServiceId: 1,
            deviceModelName: "iPhone", manufacturerName: "Apple",
            repairServiceName: "Screen", repairServiceSlug: "screen",
            baseLaborPriceCents: 5000, laborPriceCents: 5000
        )
        let r2 = RepairPricingLookupResult(
            id: 1, deviceModelId: 1, repairServiceId: 1,
            deviceModelName: "iPhone", manufacturerName: "Apple",
            repairServiceName: "Screen", repairServiceSlug: "screen",
            baseLaborPriceCents: 5000, laborPriceCents: 5000
        )
        let r3 = RepairPricingLookupResult(
            id: 2, deviceModelId: 2, repairServiceId: 2,
            deviceModelName: "Galaxy", manufacturerName: "Samsung",
            repairServiceName: "Battery", repairServiceSlug: "battery",
            baseLaborPriceCents: 3000, laborPriceCents: 3000
        )
        XCTAssertEqual(r1, r2)
        XCTAssertNotEqual(r1, r3)
    }

    // MARK: - Optional (nil) lookup result

    func test_optionalLookup_decodesNullAsNil() throws {
        // The server returns `{ "success": true, "data": null }` when no
        // price row exists. `get` unwraps the envelope → `data` is `nil`.
        // We test the DTO directly — the Optional<RepairPricingLookupResult>
        // decode from a JSON `null` literal.
        let nullData = Data("null".utf8)
        let result = try decoder.decode(RepairPricingLookupResult?.self, from: nullData)
        XCTAssertNil(result)
    }

    func test_optionalLookup_decodesObjectAsNonNil() throws {
        let json = """
        {
          "id": 99,
          "device_model_id": 5,
          "repair_service_id": 8,
          "device_model_name": "iPad Air",
          "manufacturer_name": "Apple",
          "repair_service_name": "Battery Swap",
          "repair_service_slug": "battery-swap",
          "base_labor_price": 4000,
          "labor_price": 4400,
          "adjustments": { "flat": 0, "pct": 10 },
          "grades": [],
          "default_grade": "aftermarket",
          "is_active": 1
        }
        """
        let result = try decoder.decode(RepairPricingLookupResult?.self, from: Data(json.utf8))
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, 99)
        XCTAssertEqual(result?.adjustments.pct, 10)
    }
}
