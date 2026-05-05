import XCTest
@testable import Appointments
import Networking

// MARK: - AppointmentConflictResolverTests
// TDD: written before AppointmentConflictResolver was implemented.

final class AppointmentConflictResolverTests: XCTestCase {

    // MARK: - Helpers

    private func makeInterval(
        start: Date, durationMinutes: Double
    ) -> DateInterval {
        DateInterval(start: start, duration: durationMinutes * 60)
    }

    private func makeISO() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    private func makeAppointment(
        id: Int64 = 1,
        start: Date,
        end: Date
    ) -> Appointment {
        let fmt = makeISO()
        let startStr = fmt.string(from: start)
        let endStr = fmt.string(from: end)
        let dict: [String: Any] = [
            "id": id,
            "start_time": startStr,
            "end_time": endStr
        ]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(Appointment.self, from: data)
    }

    private let base = Date(timeIntervalSince1970: 1_700_000_000) // fixed reference

    // MARK: - No conflict

    func test_noConflict_emptyList() {
        let proposed = makeInterval(start: base, durationMinutes: 60)
        XCTAssertFalse(AppointmentConflictResolver.hasConflict(proposed: proposed, existingAppointments: []))
    }

    func test_noConflict_appointmentBefore() {
        let existing = makeAppointment(
            start: base.addingTimeInterval(-120 * 60),
            end: base.addingTimeInterval(-60 * 60)
        )
        let proposed = makeInterval(start: base, durationMinutes: 60)
        XCTAssertFalse(AppointmentConflictResolver.hasConflict(proposed: proposed, existingAppointments: [existing]))
    }

    func test_noConflict_appointmentAfter() {
        let existing = makeAppointment(
            start: base.addingTimeInterval(90 * 60),
            end: base.addingTimeInterval(150 * 60)
        )
        let proposed = makeInterval(start: base, durationMinutes: 60)
        XCTAssertFalse(AppointmentConflictResolver.hasConflict(proposed: proposed, existingAppointments: [existing]))
    }

    func test_noConflict_touchingBoundary() {
        // Existing ends exactly when proposed starts — not a conflict
        let existing = makeAppointment(
            start: base.addingTimeInterval(-60 * 60),
            end: base
        )
        let proposed = makeInterval(start: base, durationMinutes: 60)
        XCTAssertFalse(AppointmentConflictResolver.hasConflict(proposed: proposed, existingAppointments: [existing]))
    }

    // MARK: - Conflicts

    func test_conflict_overlap() {
        let existing = makeAppointment(
            start: base.addingTimeInterval(30 * 60),
            end: base.addingTimeInterval(90 * 60)
        )
        let proposed = makeInterval(start: base, durationMinutes: 60)
        XCTAssertTrue(AppointmentConflictResolver.hasConflict(proposed: proposed, existingAppointments: [existing]))
    }

    func test_conflict_contained() {
        let existing = makeAppointment(
            start: base.addingTimeInterval(-30 * 60),
            end: base.addingTimeInterval(90 * 60)
        )
        let proposed = makeInterval(start: base, durationMinutes: 60)
        XCTAssertTrue(AppointmentConflictResolver.hasConflict(proposed: proposed, existingAppointments: [existing]))
    }

    func test_conflict_proposedContainsExisting() {
        let existing = makeAppointment(
            start: base.addingTimeInterval(10 * 60),
            end: base.addingTimeInterval(20 * 60)
        )
        let proposed = makeInterval(start: base, durationMinutes: 60)
        XCTAssertTrue(AppointmentConflictResolver.hasConflict(proposed: proposed, existingAppointments: [existing]))
    }

    // MARK: - filterConflicting

    func test_filterConflicting_separatesFreeAndConflicting() {
        let fmt = makeISO()
        let freeSlot = AvailabilitySlot(start: fmt.string(from: base.addingTimeInterval(3 * 3600)), end: fmt.string(from: base.addingTimeInterval(4 * 3600)))
        let conflictSlot = AvailabilitySlot(start: fmt.string(from: base.addingTimeInterval(0.5 * 3600)), end: fmt.string(from: base.addingTimeInterval(1.5 * 3600)))

        let existing = makeAppointment(
            start: base,
            end: base.addingTimeInterval(60 * 60)
        )

        let (free, conflicting) = AppointmentConflictResolver.filterConflicting(
            slots: [freeSlot, conflictSlot],
            duration: 60 * 60,
            existingAppointments: [existing]
        )

        XCTAssertEqual(free.count, 1)
        XCTAssertEqual(conflicting.count, 1)
        XCTAssertEqual(free.first?.id, freeSlot.id)
        XCTAssertEqual(conflicting.first?.id, conflictSlot.id)
    }

    func test_filterConflicting_emptySlots_returnsEmpty() {
        let (free, conflicting) = AppointmentConflictResolver.filterConflicting(
            slots: [],
            duration: 3600,
            existingAppointments: []
        )
        XCTAssertTrue(free.isEmpty)
        XCTAssertTrue(conflicting.isEmpty)
    }

    // MARK: - Edge: appointment with nil times

    func test_hasConflict_appointmentWithNilTimes_skipped() {
        let dict: [String: Any] = ["id": 1]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        let appt = try! JSONDecoder().decode(Appointment.self, from: data)
        let proposed = makeInterval(start: base, durationMinutes: 60)
        XCTAssertFalse(AppointmentConflictResolver.hasConflict(proposed: proposed, existingAppointments: [appt]))
    }
}
