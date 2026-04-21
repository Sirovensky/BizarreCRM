import XCTest
@testable import Timeclock

final class ShiftScheduleConflictCheckerTests: XCTestCase {

    // MARK: - Helpers

    private func proposed(
        employeeId: Int64 = 1,
        startAt: String,
        endAt: String
    ) -> CreateScheduledShiftBody {
        CreateScheduledShiftBody(employeeId: employeeId, startAt: startAt, endAt: endAt)
    }

    private func existing(
        id: Int64 = 1,
        employeeId: Int64 = 1,
        startAt: String,
        endAt: String
    ) -> ScheduledShift {
        ScheduledShift(id: id, employeeId: employeeId, startAt: startAt, endAt: endAt)
    }

    private func pto(
        employeeId: Int64 = 1,
        startAt: String,
        endAt: String,
        description: String = "PTO"
    ) -> PTOBlock {
        PTOBlock(employeeId: employeeId, startAt: startAt, endAt: endAt, description: description)
    }

    // MARK: - No conflicts

    func test_noConflict_differentEmployee() {
        let prop = proposed(employeeId: 1, startAt: "2026-04-20T09:00:00Z", endAt: "2026-04-20T17:00:00Z")
        let ex = existing(id: 1, employeeId: 2, startAt: "2026-04-20T09:00:00Z", endAt: "2026-04-20T17:00:00Z")
        let conflicts = ShiftScheduleConflictChecker.check(proposed: prop, existingShifts: [ex], ptoBlocks: [])
        XCTAssertTrue(conflicts.isEmpty)
    }

    func test_noConflict_adjacentShifts() {
        // Adjacent (end == start) should NOT overlap (half-open interval)
        let prop = proposed(startAt: "2026-04-20T17:00:00Z", endAt: "2026-04-20T21:00:00Z")
        let ex = existing(startAt: "2026-04-20T09:00:00Z", endAt: "2026-04-20T17:00:00Z")
        let conflicts = ShiftScheduleConflictChecker.check(proposed: prop, existingShifts: [ex], ptoBlocks: [])
        XCTAssertTrue(conflicts.isEmpty)
    }

    func test_noConflict_completelyBefore() {
        let prop = proposed(startAt: "2026-04-20T06:00:00Z", endAt: "2026-04-20T08:00:00Z")
        let ex = existing(startAt: "2026-04-20T09:00:00Z", endAt: "2026-04-20T17:00:00Z")
        let conflicts = ShiftScheduleConflictChecker.check(proposed: prop, existingShifts: [ex], ptoBlocks: [])
        XCTAssertTrue(conflicts.isEmpty)
    }

    func test_noConflict_noPTO() {
        let prop = proposed(startAt: "2026-04-20T09:00:00Z", endAt: "2026-04-20T17:00:00Z")
        let conflicts = ShiftScheduleConflictChecker.check(proposed: prop, existingShifts: [], ptoBlocks: [])
        XCTAssertTrue(conflicts.isEmpty)
    }

    // MARK: - Double-booking conflicts

    func test_doubleBooking_fullOverlap() {
        let prop = proposed(startAt: "2026-04-20T09:00:00Z", endAt: "2026-04-20T17:00:00Z")
        let ex = existing(startAt: "2026-04-20T09:00:00Z", endAt: "2026-04-20T17:00:00Z")
        let conflicts = ShiftScheduleConflictChecker.check(proposed: prop, existingShifts: [ex], ptoBlocks: [])
        XCTAssertEqual(conflicts.count, 1)
        guard case let .doubleBooking(empId, shiftId, _, _) = conflicts[0] else {
            XCTFail("Expected doubleBooking"); return
        }
        XCTAssertEqual(empId, 1)
        XCTAssertEqual(shiftId, 1)
    }

    func test_doubleBooking_partialOverlap_start() {
        // Proposed starts before existing ends
        let prop = proposed(startAt: "2026-04-20T14:00:00Z", endAt: "2026-04-20T19:00:00Z")
        let ex = existing(startAt: "2026-04-20T09:00:00Z", endAt: "2026-04-20T17:00:00Z")
        let conflicts = ShiftScheduleConflictChecker.check(proposed: prop, existingShifts: [ex], ptoBlocks: [])
        XCTAssertFalse(conflicts.isEmpty)
        XCTAssertEqual(conflicts.count, 1)
    }

    func test_doubleBooking_proposed_contains_existing() {
        // Proposed fully contains existing
        let prop = proposed(startAt: "2026-04-20T07:00:00Z", endAt: "2026-04-20T20:00:00Z")
        let ex = existing(startAt: "2026-04-20T09:00:00Z", endAt: "2026-04-20T17:00:00Z")
        let conflicts = ShiftScheduleConflictChecker.check(proposed: prop, existingShifts: [ex], ptoBlocks: [])
        XCTAssertFalse(conflicts.isEmpty)
    }

    func test_doubleBooking_existing_contains_proposed() {
        let prop = proposed(startAt: "2026-04-20T10:00:00Z", endAt: "2026-04-20T12:00:00Z")
        let ex = existing(startAt: "2026-04-20T09:00:00Z", endAt: "2026-04-20T17:00:00Z")
        let conflicts = ShiftScheduleConflictChecker.check(proposed: prop, existingShifts: [ex], ptoBlocks: [])
        XCTAssertFalse(conflicts.isEmpty)
    }

    // MARK: - PTO conflicts

    func test_ptoOverlap_exactSameTimes() {
        let prop = proposed(startAt: "2026-04-20T09:00:00Z", endAt: "2026-04-20T17:00:00Z")
        let p = pto(startAt: "2026-04-20T09:00:00Z", endAt: "2026-04-20T17:00:00Z", description: "Vacation")
        let conflicts = ShiftScheduleConflictChecker.check(proposed: prop, existingShifts: [], ptoBlocks: [p])
        XCTAssertEqual(conflicts.count, 1)
        guard case let .ptoOverlap(empId, desc) = conflicts[0] else {
            XCTFail("Expected ptoOverlap"); return
        }
        XCTAssertEqual(empId, 1)
        XCTAssertEqual(desc, "Vacation")
    }

    func test_ptoOverlap_differentEmployee_noConflict() {
        let prop = proposed(employeeId: 1, startAt: "2026-04-20T09:00:00Z", endAt: "2026-04-20T17:00:00Z")
        let p = pto(employeeId: 2, startAt: "2026-04-20T09:00:00Z", endAt: "2026-04-20T17:00:00Z")
        let conflicts = ShiftScheduleConflictChecker.check(proposed: prop, existingShifts: [], ptoBlocks: [p])
        XCTAssertTrue(conflicts.isEmpty)
    }

    func test_ptoAndDoubleBooking_bothDetected() {
        let prop = proposed(startAt: "2026-04-20T09:00:00Z", endAt: "2026-04-20T17:00:00Z")
        let ex = existing(startAt: "2026-04-20T10:00:00Z", endAt: "2026-04-20T14:00:00Z")
        let p = pto(startAt: "2026-04-20T14:00:00Z", endAt: "2026-04-20T18:00:00Z")
        let conflicts = ShiftScheduleConflictChecker.check(proposed: prop, existingShifts: [ex], ptoBlocks: [p])
        XCTAssertEqual(conflicts.count, 2)
    }

    // MARK: - Invalid ISO

    func test_invalidISO_proposed_returnsNoConflicts() {
        let prop = proposed(startAt: "not-a-date", endAt: "also-bad")
        let ex = existing(startAt: "2026-04-20T09:00:00Z", endAt: "2026-04-20T17:00:00Z")
        let conflicts = ShiftScheduleConflictChecker.check(proposed: prop, existingShifts: [ex], ptoBlocks: [])
        XCTAssertTrue(conflicts.isEmpty)
    }

    // MARK: - checkAll

    func test_checkAll_detectsIntraProposedConflict() {
        let a = proposed(employeeId: 1, startAt: "2026-04-20T09:00:00Z", endAt: "2026-04-20T17:00:00Z")
        let b = proposed(employeeId: 1, startAt: "2026-04-20T14:00:00Z", endAt: "2026-04-20T20:00:00Z")
        let conflicts = ShiftScheduleConflictChecker.checkAll(proposed: [a, b], existingShifts: [], ptoBlocks: [])
        XCTAssertFalse(conflicts.isEmpty)
    }

    func test_checkAll_noConflicts_whenNoOverlap() {
        let a = proposed(employeeId: 1, startAt: "2026-04-20T06:00:00Z", endAt: "2026-04-20T14:00:00Z")
        let b = proposed(employeeId: 1, startAt: "2026-04-20T14:00:00Z", endAt: "2026-04-20T22:00:00Z")
        let conflicts = ShiftScheduleConflictChecker.checkAll(proposed: [a, b], existingShifts: [], ptoBlocks: [])
        XCTAssertTrue(conflicts.isEmpty)
    }
}
