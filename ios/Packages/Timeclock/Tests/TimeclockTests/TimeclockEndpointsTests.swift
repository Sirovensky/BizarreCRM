import XCTest
@testable import Networking

/// Validates snake_case JSON decoding for ClockEntry and ClockStatus.
final class TimeclockEndpointsTests: XCTestCase {

    // MARK: - ClockEntry decode

    func test_clockEntry_decodesAllFields() throws {
        let json = """
        {
            "id": 42,
            "user_id": 7,
            "clock_in": "2026-04-20T09:14:00Z",
            "clock_out": "2026-04-20T17:30:00Z",
            "running_hours": null,
            "total_hours": 8.27
        }
        """
        let entry = try decode(ClockEntry.self, from: json)
        XCTAssertEqual(entry.id, 42)
        XCTAssertEqual(entry.userId, 7)
        XCTAssertEqual(entry.clockIn, "2026-04-20T09:14:00Z")
        XCTAssertEqual(entry.clockOut, "2026-04-20T17:30:00Z")
        XCTAssertNil(entry.runningHours)
        XCTAssertEqual(try XCTUnwrap(entry.totalHours), 8.27, accuracy: 0.001)
    }

    func test_clockEntry_decodesActiveRow_noClockOut() throws {
        let json = """
        {
            "id": 1,
            "user_id": 3,
            "clock_in": "2026-04-20T08:00:00Z",
            "running_hours": 1.5
        }
        """
        let entry = try decode(ClockEntry.self, from: json)
        XCTAssertEqual(entry.id, 1)
        XCTAssertNil(entry.clockOut)
        XCTAssertNil(entry.totalHours)
        XCTAssertEqual(try XCTUnwrap(entry.runningHours), 1.5, accuracy: 0.001)
    }

    func test_clockEntry_decodesMinimalRow() throws {
        let json = """
        { "id": 99, "user_id": 1, "clock_in": "2026-01-01T00:00:00Z" }
        """
        let entry = try decode(ClockEntry.self, from: json)
        XCTAssertEqual(entry.id, 99)
        XCTAssertNil(entry.clockOut)
        XCTAssertNil(entry.runningHours)
        XCTAssertNil(entry.totalHours)
    }

    // MARK: - ClockStatus decode

    func test_clockStatus_decodesActiveState() throws {
        let json = """
        {
            "is_clocked_in": true,
            "current_clock_entry": {
                "id": 5,
                "user_id": 2,
                "clock_in": "2026-04-20T09:00:00Z"
            }
        }
        """
        let status = try decode(ClockStatus.self, from: json)
        XCTAssertTrue(status.isClockedIn)
        XCTAssertNotNil(status.entry)
        XCTAssertEqual(status.entry?.id, 5)
        XCTAssertEqual(status.entry?.clockIn, "2026-04-20T09:00:00Z")
    }

    func test_clockStatus_decodesIdleState() throws {
        let json = """
        { "is_clocked_in": false, "current_clock_entry": null }
        """
        let status = try decode(ClockStatus.self, from: json)
        XCTAssertFalse(status.isClockedIn)
        XCTAssertNil(status.entry)
    }

    func test_clockStatus_missingEntry_treatedAsNil() throws {
        // Server may omit the key entirely when not clocked in.
        let json = """
        { "is_clocked_in": false }
        """
        let status = try decode(ClockStatus.self, from: json)
        XCTAssertFalse(status.isClockedIn)
        XCTAssertNil(status.entry)
    }

    // MARK: - ClockEntry Hashable / Identifiable

    func test_clockEntry_isHashable() throws {
        let e1 = ClockEntry(id: 1, userId: 1, clockIn: "2026-01-01T00:00:00Z")
        let e2 = ClockEntry(id: 1, userId: 1, clockIn: "2026-01-01T00:00:00Z")
        var set = Set<ClockEntry>()
        set.insert(e1)
        set.insert(e2)
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - Helper

    private func decode<T: Decodable>(_ type: T.Type, from jsonString: String) throws -> T {
        let data = Data(jsonString.utf8)
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }
}
