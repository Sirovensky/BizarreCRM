import XCTest
@testable import Networking

/// §43 — tests for DeviceTemplate + RepairService JSON decoding.
/// All fixtures mirror actual server snake_case column names.
final class DeviceTemplatesEndpointsTests: XCTestCase {

    // MARK: - DeviceTemplate decoding

    func test_deviceTemplate_decodesRequiredFields() throws {
        let json = """
        {
          "id": 1,
          "name": "iPhone 15 Pro Screen Replacement",
          "device_category": "Apple",
          "device_model": "iPhone 15 Pro"
        }
        """.data(using: .utf8)!
        let t = try decode(DeviceTemplate.self, from: json)
        XCTAssertEqual(t.id, 1)
        XCTAssertEqual(t.name, "iPhone 15 Pro Screen Replacement")
        XCTAssertEqual(t.family, "Apple")
        XCTAssertEqual(t.model, "iPhone 15 Pro")
        XCTAssertNil(t.thumbnailUrl)
        XCTAssertNil(t.imeiPattern)
        XCTAssertNil(t.services)
        XCTAssertTrue(t.conditions.isEmpty)
    }

    func test_deviceTemplate_decodesOptionalFields() throws {
        let json = """
        {
          "id": 2,
          "name": "Galaxy S24 Battery",
          "device_category": "Samsung",
          "device_model": "Galaxy S24",
          "color": "Titanium Black",
          "thumbnail_url": "https://cdn.example.com/s24.png",
          "imei_pattern": "^35",
          "warranty_days": 90,
          "suggested_price": 7999
        }
        """.data(using: .utf8)!
        let t = try decode(DeviceTemplate.self, from: json)
        XCTAssertEqual(t.id, 2)
        XCTAssertEqual(t.family, "Samsung")
        XCTAssertEqual(t.color, "Titanium Black")
        XCTAssertEqual(t.thumbnailUrl, "https://cdn.example.com/s24.png")
        XCTAssertEqual(t.imeiPattern, "^35")
        XCTAssertEqual(t.warrantyDays, 90)
        XCTAssertEqual(t.defaultPriceCents, 7999)
    }

    func test_deviceTemplate_decodesConditionsArray() throws {
        let json = """
        {
          "id": 3,
          "name": "Pixel 8 Charging Port",
          "device_category": "Google",
          "device_model": "Pixel 8",
          "diagnostic_checklist": ["Check USB-C", "Test fast charge", "Inspect pins"]
        }
        """.data(using: .utf8)!
        let t = try decode(DeviceTemplate.self, from: json)
        XCTAssertEqual(t.conditions, ["Check USB-C", "Test fast charge", "Inspect pins"])
    }

    func test_deviceTemplate_emptyConditionsFallback() throws {
        // `diagnostic_checklist` absent → empty array (not a crash)
        let json = """
        { "id": 4, "name": "Test Device", "device_category": "Other" }
        """.data(using: .utf8)!
        let t = try decode(DeviceTemplate.self, from: json)
        XCTAssertTrue(t.conditions.isEmpty)
    }

    func test_deviceTemplate_decodesNestedServices() throws {
        let json = """
        {
          "id": 5,
          "name": "iPhone 14 Battery Swap",
          "device_category": "Apple",
          "device_model": "iPhone 14",
          "services": [
            {
              "id": 10,
              "service_name": "Battery Replacement",
              "default_price_cents": 5900,
              "part_sku": "APL-BAT-IP14"
            }
          ]
        }
        """.data(using: .utf8)!
        let t = try decode(DeviceTemplate.self, from: json)
        XCTAssertEqual(t.services?.count, 1)
        XCTAssertEqual(t.services?.first?.serviceName, "Battery Replacement")
        XCTAssertEqual(t.services?.first?.defaultPriceCents, 5900)
        XCTAssertEqual(t.services?.first?.partSku, "APL-BAT-IP14")
    }

    func test_deviceTemplate_missingServicesIsNil() throws {
        let json = """
        { "id": 6, "name": "No Services", "device_category": "Apple" }
        """.data(using: .utf8)!
        let t = try decode(DeviceTemplate.self, from: json)
        XCTAssertNil(t.services)
    }

    func test_deviceTemplate_warrantyDaysDefaultsTo30() throws {
        let json = """
        { "id": 7, "name": "Default Warranty", "device_category": "Apple" }
        """.data(using: .utf8)!
        let t = try decode(DeviceTemplate.self, from: json)
        XCTAssertEqual(t.warrantyDays, 30)
    }

    // MARK: - RepairService decoding

    func test_repairService_decodesAllFields() throws {
        let json = """
        {
          "id": 100,
          "family": "Apple",
          "model": "iPhone 15",
          "service_name": "Screen Replacement",
          "default_price_cents": 19900,
          "part_sku": "APL-SCR-IP15",
          "estimated_minutes": 45
        }
        """.data(using: .utf8)!
        let s = try decode(RepairService.self, from: json)
        XCTAssertEqual(s.id, 100)
        XCTAssertEqual(s.family, "Apple")
        XCTAssertEqual(s.model, "iPhone 15")
        XCTAssertEqual(s.serviceName, "Screen Replacement")
        XCTAssertEqual(s.defaultPriceCents, 19900)
        XCTAssertEqual(s.partSku, "APL-SCR-IP15")
        XCTAssertEqual(s.estimatedMinutes, 45)
    }

    func test_repairService_optionalFieldsMissing() throws {
        let json = """
        {
          "id": 200,
          "service_name": "Diagnostic Check",
          "default_price_cents": 2500
        }
        """.data(using: .utf8)!
        let s = try decode(RepairService.self, from: json)
        XCTAssertEqual(s.id, 200)
        XCTAssertNil(s.family)
        XCTAssertNil(s.model)
        XCTAssertNil(s.partSku)
        XCTAssertNil(s.estimatedMinutes)
    }

    func test_repairService_zeroCentsIsValid() throws {
        let json = """
        {
          "id": 300,
          "service_name": "Free Diagnostic",
          "default_price_cents": 0
        }
        """.data(using: .utf8)!
        let s = try decode(RepairService.self, from: json)
        XCTAssertEqual(s.defaultPriceCents, 0)
    }

    func test_repairService_identifiableAndHashable() throws {
        let s1 = RepairService(id: 1, serviceName: "Screen", defaultPriceCents: 100)
        let s2 = RepairService(id: 1, serviceName: "Screen", defaultPriceCents: 100)
        let s3 = RepairService(id: 2, serviceName: "Battery", defaultPriceCents: 200)
        XCTAssertEqual(s1, s2)
        XCTAssertNotEqual(s1, s3)
        var set = Set<RepairService>()
        set.insert(s1)
        set.insert(s2)
        XCTAssertEqual(set.count, 1)
    }

    func test_deviceTemplate_identifiableAndHashable() throws {
        let t1 = DeviceTemplate(id: 1, name: "iPhone", family: "Apple", model: "15")
        let t2 = DeviceTemplate(id: 1, name: "iPhone", family: "Apple", model: "15")
        let t3 = DeviceTemplate(id: 2, name: "Galaxy", family: "Samsung", model: "S24")
        XCTAssertEqual(t1, t2)
        XCTAssertNotEqual(t1, t3)
    }

    // MARK: - Array decode (list endpoint)

    func test_decodesTemplateArray() throws {
        let json = """
        [
          { "id": 1, "name": "A", "device_category": "Apple" },
          { "id": 2, "name": "B", "device_category": "Samsung" }
        ]
        """.data(using: .utf8)!
        let templates = try decode([DeviceTemplate].self, from: json)
        XCTAssertEqual(templates.count, 2)
        XCTAssertEqual(templates[0].family, "Apple")
        XCTAssertEqual(templates[1].family, "Samsung")
    }

    func test_decodesRepairServiceArray() throws {
        let json = """
        [
          { "id": 1, "service_name": "Screen", "default_price_cents": 9900 },
          { "id": 2, "service_name": "Battery", "default_price_cents": 5900 },
          { "id": 3, "service_name": "Port", "default_price_cents": 7900 }
        ]
        """.data(using: .utf8)!
        let services = try decode([RepairService].self, from: json)
        XCTAssertEqual(services.count, 3)
        XCTAssertEqual(services.map(\.defaultPriceCents), [9900, 5900, 7900])
    }

    // MARK: - Helper

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let d = JSONDecoder()
        // The server uses snake_case; our CodingKeys handle mapping.
        // We intentionally do NOT use `.convertFromSnakeCase` to validate
        // that explicit CodingKeys are correct.
        return try d.decode(type, from: data)
    }
}
