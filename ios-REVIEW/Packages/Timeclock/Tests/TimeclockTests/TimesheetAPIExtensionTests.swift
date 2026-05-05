import XCTest
@testable import Networking

// MARK: - TimesheetAPIExtensionTests
//
// Validates encode/decode of types added in APIClient+Timeclock.swift.

final class TimesheetAPIExtensionTests: XCTestCase {

    // MARK: - ClockEntryEditRequest encoding

    func test_clockEntryEditRequest_encodesAllFields() throws {
        let edit = ClockEntryEditRequest(
            clockIn:  "2026-04-21T09:00:00Z",
            clockOut: "2026-04-21T17:00:00Z",
            notes:    "Corrected at manager request",
            reason:   "Employee forgot to clock out"
        )
        let data = try JSONEncoder().encode(edit)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(dict["clock_in"]  as? String, "2026-04-21T09:00:00Z")
        XCTAssertEqual(dict["clock_out"] as? String, "2026-04-21T17:00:00Z")
        XCTAssertEqual(dict["notes"]     as? String, "Corrected at manager request")
        XCTAssertEqual(dict["reason"]    as? String, "Employee forgot to clock out")
    }

    func test_clockEntryEditRequest_nilFieldsOmitted() throws {
        let edit = ClockEntryEditRequest(reason: "Just updating reason")
        let data = try JSONEncoder().encode(edit)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNil(dict["clock_in"])
        XCTAssertNil(dict["clock_out"])
        XCTAssertNil(dict["notes"])
        XCTAssertEqual(dict["reason"] as? String, "Just updating reason")
    }

    func test_clockEntryEditRequest_clockInOnly() throws {
        let edit = ClockEntryEditRequest(
            clockIn: "2026-04-21T08:45:00Z",
            reason: "Employee arrived earlier"
        )
        let data = try JSONEncoder().encode(edit)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(dict["clock_in"] as? String, "2026-04-21T08:45:00Z")
        XCTAssertNil(dict["clock_out"])
        XCTAssertEqual(dict["reason"] as? String, "Employee arrived earlier")
    }

    func test_clockEntryEditRequest_clockOutOnly() throws {
        let edit = ClockEntryEditRequest(
            clockOut: "2026-04-21T18:00:00Z",
            reason:   "Late clock-out correction"
        )
        let data = try JSONEncoder().encode(edit)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNil(dict["clock_in"])
        XCTAssertEqual(dict["clock_out"] as? String, "2026-04-21T18:00:00Z")
        XCTAssertEqual(dict["reason"]    as? String, "Late clock-out correction")
    }

    // MARK: - ClockEntry decode (verifies listClockEntries return type)

    func test_clockEntryArray_decodes() throws {
        let json = """
        [
            {
                "id": 1,
                "user_id": 10,
                "clock_in": "2026-04-21T08:00:00Z",
                "clock_out": "2026-04-21T16:00:00Z",
                "total_hours": 8.0
            },
            {
                "id": 2,
                "user_id": 10,
                "clock_in": "2026-04-22T09:00:00Z"
            }
        ]
        """
        let data = Data(json.utf8)
        let entries = try JSONDecoder().decode([ClockEntry].self, from: data)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].id, 1)
        XCTAssertEqual(entries[0].totalHours, 8.0, accuracy: 0.001)
        XCTAssertNil(entries[1].clockOut)
        XCTAssertNil(entries[1].totalHours)
    }

    func test_clockEntryArray_decodesEmpty() throws {
        let json = "[]"
        let entries = try JSONDecoder().decode([ClockEntry].self, from: Data(json.utf8))
        XCTAssertTrue(entries.isEmpty)
    }
}
