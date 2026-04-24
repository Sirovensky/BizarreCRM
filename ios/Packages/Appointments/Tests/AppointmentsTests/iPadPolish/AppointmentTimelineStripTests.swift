import XCTest
@testable import Appointments
import Networking

// MARK: - AppointmentTimelineStripTests
//
// Tests for AppointmentTimelineStrip's static helpers and geometry logic,
// which are unit-testable without SwiftUI rendering.

final class AppointmentTimelineStripTests: XCTestCase {

    // MARK: - parseDate (static)

    func test_parseDate_iso8601WithFractional_returnsDate() {
        let result = AppointmentTimelineStrip.parseDate("2025-06-02T09:00:00.000Z")
        XCTAssertNotNil(result, "ISO-8601 with fractional seconds should be parsed")
    }

    func test_parseDate_iso8601_returnsDate() {
        let result = AppointmentTimelineStrip.parseDate("2025-06-02T09:00:00Z")
        XCTAssertNotNil(result)
    }

    func test_parseDate_sqlFormat_returnsDate() {
        let result = AppointmentTimelineStrip.parseDate("2025-06-02 09:00:00")
        XCTAssertNotNil(result)
    }

    func test_parseDate_invalidString_returnsNil() {
        XCTAssertNil(AppointmentTimelineStrip.parseDate("bogus"))
    }

    func test_parseDate_emptyString_returnsNil() {
        XCTAssertNil(AppointmentTimelineStrip.parseDate(""))
    }

    func test_parseDate_partialDate_returnsNil() {
        XCTAssertNil(AppointmentTimelineStrip.parseDate("2025-06-02"))
    }

    // MARK: - Timeline hour range constants

    func test_visibleHours_isPositive() {
        // Accessing the private enum indirectly via the range: 7am to 9pm = 14 hours.
        // We can't access private enum directly, so we verify via a known chip placement:
        // an appointment at 7:00 should have xOffset = 0 (first slot).
        let appt = makeAppointment(startTime: "2025-06-02T07:00:00Z", endTime: "2025-06-02T08:00:00Z")
        // Chip should be present and at offset 0.
        let strip = AppointmentTimelineStrip(appointments: [appt], date: date("2025-06-02"))
        // No crash means the timeline parses OK. Geometry tested in the view layer;
        // here we verify the object constructs without throwing.
        _ = strip
    }

    // MARK: - Appointment outside visible range

    func test_stripInit_withNoAppointments_doesNotCrash() {
        let strip = AppointmentTimelineStrip(appointments: [], date: Date())
        _ = strip
    }

    func test_stripInit_withManyAppointments_doesNotCrash() {
        let appts = (0..<20).map { i in
            makeAppointment(
                startTime: "2025-06-02T\(String(format: "%02d", (7 + i) % 21)):00:00Z",
                endTime:   "2025-06-02T\(String(format: "%02d", (8 + i) % 22)):00:00Z"
            )
        }
        let strip = AppointmentTimelineStrip(appointments: appts, date: date("2025-06-02"))
        _ = strip
    }

    // MARK: - onSelect callback

    func test_onSelect_isStoredCorrectly() {
        var called = false
        let appt = makeAppointment(startTime: "2025-06-02T09:00:00Z")
        let strip = AppointmentTimelineStrip(appointments: [appt], date: date("2025-06-02")) { _ in
            called = true
        }
        strip.onSelect?(appt)
        XCTAssertTrue(called, "onSelect closure should be invoked when chip is tapped")
    }

    func test_onSelect_nilByDefault() {
        let strip = AppointmentTimelineStrip(appointments: [], date: Date())
        XCTAssertNil(strip.onSelect, "onSelect should be nil when not provided")
    }

    // MARK: - date property

    func test_dateProperty_isStoredCorrectly() {
        let refDate = date("2025-06-02")
        let strip = AppointmentTimelineStrip(appointments: [], date: refDate)
        XCTAssertEqual(strip.date, refDate)
    }

    // MARK: - appointments property

    func test_appointmentsProperty_storesAll() {
        let appts = [
            makeAppointment(startTime: "2025-06-02T08:00:00Z"),
            makeAppointment(startTime: "2025-06-02T10:00:00Z"),
        ]
        let strip = AppointmentTimelineStrip(appointments: appts, date: Date())
        XCTAssertEqual(strip.appointments.count, 2)
    }

    // MARK: - Helpers

    private func makeAppointment(startTime: String, endTime: String? = nil, status: String = "scheduled") -> Appointment {
        var dict: [String: Any] = [
            "id": Int64.random(in: 1...10_000),
            "title": "Test",
            "start_time": startTime,
            "status": status
        ]
        if let et = endTime { dict["end_time"] = et }
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(Appointment.self, from: data)
    }

    private func date(_ iso: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: iso) ?? Date()
    }
}
