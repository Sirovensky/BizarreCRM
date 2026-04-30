import XCTest
@testable import Inventory

// MARK: - InventoryAssetTests
// §6.8 — Asset model correctness + status helpers.

final class InventoryAssetTests: XCTestCase {

    // MARK: - Helpers

    private func makeAsset(status: AssetStatus, loanedTo: String? = nil) -> InventoryAsset {
        InventoryAsset(
            id: Int64.random(in: 1...9999),
            name: "Test Loaner",
            serial: "SN12345",
            status: status,
            createdAt: Date(),
            updatedAt: Date(),
            loanedTo: loanedTo
        )
    }

    // MARK: - AssetStatus

    func test_availableStatus_isAvailableForIssue() {
        let asset = makeAsset(status: .available)
        XCTAssertTrue(asset.status.isAvailableForIssue)
    }

    func test_loanedStatus_notAvailableForIssue() {
        let asset = makeAsset(status: .loaned)
        XCTAssertFalse(asset.status.isAvailableForIssue)
    }

    func test_retiredStatus_notAvailableForIssue() {
        let asset = makeAsset(status: .retired)
        XCTAssertFalse(asset.status.isAvailableForIssue)
    }

    func test_allCases_count() {
        XCTAssertEqual(AssetStatus.allCases.count, 3)
    }

    func test_displayNames_areNonEmpty() {
        for s in AssetStatus.allCases {
            XCTAssertFalse(s.displayName.isEmpty, "\(s) displayName should not be empty")
        }
    }

    // MARK: - Model fields

    func test_asset_loanedTo_reflects() {
        let asset = makeAsset(status: .loaned, loanedTo: "Jane Smith")
        XCTAssertEqual(asset.loanedTo, "Jane Smith")
    }

    func test_asset_available_noLoanedTo() {
        let asset = makeAsset(status: .available)
        XCTAssertNil(asset.loanedTo)
    }

    // MARK: - UpsertAssetRequest encoding

    func test_upsertRequest_encodes_snakeCase() throws {
        let req = UpsertAssetRequest(
            name: "Loaner #1",
            serial: "SN001",
            imei: nil,
            condition: "Good",
            status: .available,
            notes: "No scratches"
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["name"] as? String, "Loaner #1")
        XCTAssertEqual(json["serial"] as? String, "SN001")
        XCTAssertEqual(json["condition"] as? String, "Good")
        XCTAssertEqual(json["status"] as? String, "available")
        XCTAssertEqual(json["notes"] as? String, "No scratches")
        XCTAssertNil(json["imei"])
    }

    // MARK: - LoanAssetRequest encoding

    func test_loanRequest_encodes_snakeCase() throws {
        let req = LoanAssetRequest(
            ticketDeviceId: 42,
            customerId: 7,
            conditionOut: "Good",
            notes: "Handled with care"
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["ticket_device_id"] as? Int, 42)
        XCTAssertEqual(json["customer_id"] as? Int, 7)
        XCTAssertEqual(json["condition_out"] as? String, "Good")
        XCTAssertEqual(json["notes"] as? String, "Handled with care")
    }

    // MARK: - ReturnAssetRequest encoding

    func test_returnRequest_encodes_snakeCase() throws {
        let req = ReturnAssetRequest(
            conditionIn: "Minor scratch",
            newStatus: .available,
            notes: "Returned in good condition"
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["condition_in"] as? String, "Minor scratch")
        XCTAssertEqual(json["new_status"] as? String, "available")
        XCTAssertEqual(json["notes"] as? String, "Returned in good condition")
    }

    // MARK: - Decoding

    func test_asset_decodes_from_json() throws {
        let json = """
        {
            "id": 1,
            "name": "Loaner Phone",
            "serial": "ABCDEF",
            "imei": null,
            "condition": "Good",
            "status": "available",
            "notes": null,
            "created_at": "2025-01-06T09:00:00Z",
            "updated_at": "2025-01-06T09:00:00Z",
            "is_loaned_out": false,
            "loaned_to": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let asset = try decoder.decode(InventoryAsset.self, from: json)

        XCTAssertEqual(asset.id, 1)
        XCTAssertEqual(asset.name, "Loaner Phone")
        XCTAssertEqual(asset.serial, "ABCDEF")
        XCTAssertEqual(asset.status, .available)
        XCTAssertNil(asset.loanedTo)
        XCTAssertEqual(asset.isLoanedOut, false)
    }

    func test_asset_decodes_loaned_status() throws {
        let json = """
        {
            "id": 2,
            "name": "Loaner Tablet",
            "serial": "XY9999",
            "imei": null,
            "condition": "Fair",
            "status": "loaned",
            "notes": null,
            "created_at": "2025-01-06T09:00:00Z",
            "updated_at": "2025-01-06T09:00:00Z",
            "is_loaned_out": true,
            "loaned_to": "Alice Brown"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let asset = try decoder.decode(InventoryAsset.self, from: json)

        XCTAssertEqual(asset.status, .loaned)
        XCTAssertEqual(asset.loanedTo, "Alice Brown")
        XCTAssertEqual(asset.isLoanedOut, true)
    }
}
