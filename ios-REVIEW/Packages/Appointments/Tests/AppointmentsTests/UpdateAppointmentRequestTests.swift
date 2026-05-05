import XCTest
@testable import Appointments
import Networking

// MARK: - UpdateAppointmentRequestTests
//
// Verifies that UpdateAppointmentRequest serialises to correct snake_case
// JSON and that nil fields are omitted (sparse PUT semantics).

final class UpdateAppointmentRequestTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    private func encode(_ req: UpdateAppointmentRequest) throws -> [String: Any] {
        let data = try encoder.encode(req)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Sparse encoding

    func test_encodeStatusOnly_containsStatusKey() throws {
        let req = UpdateAppointmentRequest(status: "cancelled")
        let dict = try encode(req)
        XCTAssertEqual(dict["status"] as? String, "cancelled")
        XCTAssertEqual(dict.count, 1, "Only the non-nil field should be present")
    }

    func test_encodeNoShow_containsSnakeCaseKey() throws {
        let req = UpdateAppointmentRequest(noShow: true)
        let dict = try encode(req)
        XCTAssertEqual(dict["no_show"] as? Bool, true)
        XCTAssertEqual(dict.count, 1)
    }

    func test_encodeStartAndEnd_keysAreSnakeCase() throws {
        let req = UpdateAppointmentRequest(
            startTime: "2025-09-01T09:00:00Z",
            endTime: "2025-09-01T10:00:00Z"
        )
        let dict = try encode(req)
        XCTAssertEqual(dict["start_time"] as? String, "2025-09-01T09:00:00Z")
        XCTAssertEqual(dict["end_time"]   as? String, "2025-09-01T10:00:00Z")
        XCTAssertEqual(dict.count, 2)
    }

    func test_encodeAssignedTo_keyIsSnakeCase() throws {
        let req = UpdateAppointmentRequest(assignedTo: 42)
        let dict = try encode(req)
        XCTAssertEqual(dict["assigned_to"] as? Int64, 42)
        XCTAssertEqual(dict.count, 1)
    }

    func test_encodeAllNil_producesEmptyObject() throws {
        let req = UpdateAppointmentRequest()
        let dict = try encode(req)
        XCTAssertEqual(dict.count, 0, "All-nil request should encode as empty JSON object")
    }

    func test_encodeFullPayload_allFieldsPresent() throws {
        let req = UpdateAppointmentRequest(
            title: "Renamed",
            startTime: "2025-09-01T09:00:00Z",
            endTime: "2025-09-01T10:00:00Z",
            customerId: 1,
            leadId: 2,
            assignedTo: 3,
            status: "confirmed",
            notes: "Call first",
            noShow: false
        )
        let dict = try encode(req)
        XCTAssertEqual(dict["title"]       as? String, "Renamed")
        XCTAssertEqual(dict["start_time"]  as? String, "2025-09-01T09:00:00Z")
        XCTAssertEqual(dict["end_time"]    as? String, "2025-09-01T10:00:00Z")
        XCTAssertEqual(dict["customer_id"] as? Int64, 1)
        XCTAssertEqual(dict["lead_id"]     as? Int64, 2)
        XCTAssertEqual(dict["assigned_to"] as? Int64, 3)
        XCTAssertEqual(dict["status"]      as? String, "confirmed")
        XCTAssertEqual(dict["notes"]       as? String, "Call first")
        XCTAssertEqual(dict["no_show"]     as? Bool, false)
        XCTAssertEqual(dict.count, 9)
    }

    // MARK: - AppointmentStatus raw values

    func test_appointmentStatus_rawValues() {
        XCTAssertEqual(AppointmentStatus.scheduled.rawValue, "scheduled")
        XCTAssertEqual(AppointmentStatus.confirmed.rawValue, "confirmed")
        XCTAssertEqual(AppointmentStatus.completed.rawValue, "completed")
        XCTAssertEqual(AppointmentStatus.cancelled.rawValue, "cancelled")
        XCTAssertEqual(AppointmentStatus.noShow.rawValue,    "no-show")
    }
}
