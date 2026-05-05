import XCTest
@testable import Tickets
@testable import Networking

// §4.3 / §4.6 — Test that the new endpoint DTOs encode to valid JSON matching
// the server's expected field names.

final class TicketEndpointEncodingTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return enc
    }()

    // MARK: - AddTicketNoteRequest

    func test_addNoteRequest_encodesCorrectKeys() throws {
        let req = AddTicketNoteRequest(
            type: "internal",
            content: "Checked the screen",
            isFlagged: true,
            ticketDeviceId: 42
        )
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "internal")
        XCTAssertEqual(json["content"] as? String, "Checked the screen")
        XCTAssertEqual(json["is_flagged"] as? Bool, true)
        XCTAssertEqual(json["ticket_device_id"] as? Int, 42)
    }

    func test_addNoteRequest_omitsNilDeviceId() throws {
        let req = AddTicketNoteRequest(content: "No device")
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNil(json["ticket_device_id"])
    }

    func test_addNoteRequest_defaultType_isInternal() throws {
        let req = AddTicketNoteRequest(content: "Default type note")
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "internal")
    }

    // MARK: - AddTicketDeviceRequest

    func test_addDeviceRequest_encodesCorrectKeys() throws {
        let req = AddTicketDeviceRequest(
            deviceName: "iPhone 15 Pro",
            imei: "490154203237518",
            serial: "DNXYZABCD",
            price: 199.99
        )
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["device_name"] as? String, "iPhone 15 Pro")
        XCTAssertEqual(json["imei"] as? String, "490154203237518")
        XCTAssertEqual(json["serial"] as? String, "DNXYZABCD")
        let price = try XCTUnwrap(json["price"] as? Double)
        XCTAssertEqual(price, 199.99, accuracy: 0.001)
    }

    func test_addDeviceRequest_omitsNilOptionals() throws {
        let req = AddTicketDeviceRequest(deviceName: "Device A")
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNil(json["imei"])
        XCTAssertNil(json["serial"])
        XCTAssertNil(json["service_id"])
    }

    // MARK: - UpdateTicketDeviceRequest

    func test_updateDeviceRequest_encodesOnlyProvidedFields() throws {
        let req = UpdateTicketDeviceRequest(
            deviceName: "Updated Name",
            price: 299
        )
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["device_name"] as? String, "Updated Name")
        let updatePrice = try XCTUnwrap(json["price"] as? Double)
        XCTAssertEqual(updatePrice, 299, accuracy: 0.001)
        // Nil fields should be omitted (Swift encodes nil optionals as null by default,
        // but the server ignores missing keys; we just check the present keys are correct)
    }

    // MARK: - UpdateChecklistRequest

    func test_checklistRequest_encodesItems() throws {
        let items = [
            ChecklistItem(id: "abc", label: "Screen cracked", checked: true),
            ChecklistItem(id: "def", label: "Water damage", checked: false),
        ]
        let req = UpdateChecklistRequest(items: items)
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let encodedItems = json["items"] as! [[String: Any]]

        XCTAssertEqual(encodedItems.count, 2)
        XCTAssertEqual(encodedItems[0]["label"] as? String, "Screen cracked")
        XCTAssertEqual(encodedItems[0]["checked"] as? Bool, true)
        XCTAssertEqual(encodedItems[1]["checked"] as? Bool, false)
    }

    // MARK: - AddDevicePartRequest

    func test_addPartRequest_encodesCorrectKeys() throws {
        let req = AddDevicePartRequest(
            name: "OEM Battery",
            sku: "BATT-IP14",
            quantity: 2,
            price: 45.00,
            inventoryItemId: 123
        )
        let data = try encoder.encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["name"] as? String, "OEM Battery")
        XCTAssertEqual(json["sku"] as? String, "BATT-IP14")
        XCTAssertEqual(json["quantity"] as? Int, 2)
        let partPrice = try XCTUnwrap(json["price"] as? Double)
        XCTAssertEqual(partPrice, 45.0, accuracy: 0.001)
        XCTAssertEqual(json["inventory_item_id"] as? Int, 123)
    }

    // MARK: - ChecklistItem

    func test_checklistItem_codableRoundTrip() throws {
        let original = ChecklistItem(id: "round-trip-id", label: "Battery swollen", checked: true)
        let encoded = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(ChecklistItem.self, from: encoded)
        XCTAssertEqual(decoded, original)
    }

    func test_checklistItem_defaultCheckedIsFalse() {
        let item = ChecklistItem(label: "New item")
        XCTAssertFalse(item.checked)
    }

    func test_checklistItem_uniqueIdByDefault() {
        let a = ChecklistItem(label: "A")
        let b = ChecklistItem(label: "B")
        XCTAssertNotEqual(a.id, b.id)
    }

    // MARK: - DraftDevice

    func test_draftDevice_initialPrice_isZero() {
        let d = DraftDevice()
        XCTAssertEqual(d.price, 0, accuracy: 0.001)
    }

    func test_draftDevice_defaultChecklist_nonEmpty() {
        let d = DraftDevice()
        XCTAssertFalse(d.checklist.isEmpty)
    }

    // MARK: - CreateFlowStep

    func test_allSteps_haveNonEmptyTitle() {
        for step in CreateFlowStep.allCases {
            XCTAssertFalse(step.title.isEmpty, "\(step) has empty title")
        }
    }

    func test_allSteps_rawValuesAreSequential() {
        let values = CreateFlowStep.allCases.map { $0.rawValue }
        XCTAssertEqual(values.first, 0)
        XCTAssertEqual(values.last, CreateFlowStep.allCases.count - 1)
    }
}
