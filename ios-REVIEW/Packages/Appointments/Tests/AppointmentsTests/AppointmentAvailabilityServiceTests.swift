import XCTest
@testable import Appointments

// MARK: - AppointmentAvailabilityServiceTests
// TDD for §10.8 — pure service; no networking required.

final class AppointmentAvailabilityServiceTests: XCTestCase {

    // MARK: - Helpers

    private let iso = ISO8601DateFormatter()

    /// Fixed reference date: Mon 2025-01-06T09:00:00Z
    private var base: Date {
        iso.date(from: "2025-01-06T09:00:00Z")!
    }

    private func slot(startOffset: TimeInterval, endOffset: TimeInterval) -> AvailabilitySlot {
        let s = base.addingTimeInterval(startOffset)
        let e = base.addingTimeInterval(endOffset)
        return AvailabilitySlot(start: iso.string(from: s), end: iso.string(from: e))
    }

    private func blackout(label: String, startOffset: TimeInterval, endOffset: TimeInterval) -> AppointmentBlackoutDate {
        AppointmentBlackoutDate(
            id: Int64.random(in: 1...9999),
            label: label,
            start: base.addingTimeInterval(startOffset),
            end:   base.addingTimeInterval(endOffset)
        )
    }

    // MARK: - Buffer tests

    func test_applyBuffer_noBuffer_returnsAllSlots() {
        let slots = [
            slot(startOffset: 0, endOffset: 3600),    // 1h
            slot(startOffset: 3600, endOffset: 7200)  // 1h
        ]
        let result = AppointmentAvailabilityService.applyBuffer(to: slots, bufferMinutes: 0)
        XCTAssertEqual(result.count, 2)
    }

    func test_applyBuffer_shrinksSlotsEnd() {
        // 1h slot with 15min buffer → 45min usable
        let s = slot(startOffset: 0, endOffset: 3600)
        let result = AppointmentAvailabilityService.applyBuffer(to: [s], bufferMinutes: 15)
        XCTAssertEqual(result.count, 1)
        let endDate = iso.date(from: result[0].end)!
        let startDate = iso.date(from: result[0].start)!
        XCTAssertEqual(endDate.timeIntervalSince(startDate), 2700, accuracy: 1) // 45 min
    }

    func test_applyBuffer_dropsSlotsShorterThanMinDuration() {
        // 20min slot with 15min buffer → 5min remaining, below 15min minimum
        let s = slot(startOffset: 0, endOffset: 1200)  // 20 min
        let result = AppointmentAvailabilityService.applyBuffer(
            to: [s], bufferMinutes: 15, minDuration: 900
        )
        XCTAssertTrue(result.isEmpty)
    }

    func test_applyBuffer_keepsSlotsThatMeetMinDuration() {
        // 30min slot with 15min buffer → 15min remaining, exactly at minimum
        let s = slot(startOffset: 0, endOffset: 1800)  // 30 min
        let result = AppointmentAvailabilityService.applyBuffer(
            to: [s], bufferMinutes: 15, minDuration: 900
        )
        XCTAssertEqual(result.count, 1)
    }

    func test_applyBuffer_multipleSlots_allShrunk() {
        let slots = [
            slot(startOffset: 0,    endOffset: 3600),  // 1h
            slot(startOffset: 3600, endOffset: 7200),  // 1h
            slot(startOffset: 7200, endOffset: 10800)  // 1h
        ]
        let result = AppointmentAvailabilityService.applyBuffer(to: slots, bufferMinutes: 10)
        XCTAssertEqual(result.count, 3)
        // Each slot should be 50 min (3000s) after 10min buffer
        for r in result {
            let start = iso.date(from: r.start)!
            let end   = iso.date(from: r.end)!
            XCTAssertEqual(end.timeIntervalSince(start), 3000, accuracy: 1)
        }
    }

    // MARK: - Blackout filter tests

    func test_filterBlackouts_noBlackouts_returnsAll() {
        let slots = [slot(startOffset: 0, endOffset: 3600)]
        let result = AppointmentAvailabilityService.filterBlackouts(slots: slots, blackouts: [])
        XCTAssertEqual(result.count, 1)
    }

    func test_filterBlackouts_slotFullyInsideBlackout_dropped() {
        let s = slot(startOffset: 3600, endOffset: 7200)  // 10:00-11:00
        let b = blackout(label: "Holiday", startOffset: 0, endOffset: 86400)  // all day
        let result = AppointmentAvailabilityService.filterBlackouts(slots: [s], blackouts: [b])
        XCTAssertTrue(result.isEmpty)
    }

    func test_filterBlackouts_slotOutsideBlackout_kept() {
        let s = slot(startOffset: 0, endOffset: 3600)          // 09:00-10:00
        let b = blackout(label: "Afternoon", startOffset: 14400, endOffset: 18000)  // 13:00-14:00
        let result = AppointmentAvailabilityService.filterBlackouts(slots: [s], blackouts: [b])
        XCTAssertEqual(result.count, 1)
    }

    func test_filterBlackouts_slotPartiallyOverlapsBlackout_dropped() {
        // Slot 10:00-12:00, blackout 11:00-13:00 → partial overlap → drop
        let s = slot(startOffset: 3600, endOffset: 10800)
        let b = blackout(label: "Event", startOffset: 7200, endOffset: 14400)
        let result = AppointmentAvailabilityService.filterBlackouts(slots: [s], blackouts: [b])
        XCTAssertTrue(result.isEmpty)
    }

    func test_filterBlackouts_multipleBlackouts_filtersCorrectly() {
        let slots = [
            slot(startOffset: 0,     endOffset: 3600),   // 09:00-10:00 (clear)
            slot(startOffset: 7200,  endOffset: 10800),  // 11:00-12:00 (inside blackout 1)
            slot(startOffset: 18000, endOffset: 21600),  // 14:00-15:00 (inside blackout 2)
            slot(startOffset: 25200, endOffset: 28800)   // 16:00-17:00 (clear)
        ]
        let blackouts = [
            blackout(label: "Morning event",   startOffset: 6000,  endOffset: 12600),
            blackout(label: "Afternoon event", startOffset: 16200, endOffset: 22000)
        ]
        let result = AppointmentAvailabilityService.filterBlackouts(slots: slots, blackouts: blackouts)
        XCTAssertEqual(result.count, 2)
    }

    // MARK: - isBlackedOut tests

    func test_isBlackedOut_dateInsideBlackout_returnsTrue() {
        let blackouts = [blackout(label: "Holiday", startOffset: 0, endOffset: 86400)]
        XCTAssertTrue(AppointmentAvailabilityService.isBlackedOut(base, blackouts: blackouts))
    }

    func test_isBlackedOut_dateOutsideBlackout_returnsFalse() {
        // blackout is tomorrow
        let blackouts = [blackout(label: "Tomorrow", startOffset: 86400, endOffset: 172800)]
        XCTAssertFalse(AppointmentAvailabilityService.isBlackedOut(base, blackouts: blackouts))
    }

    func test_isBlackedOut_emptyBlackouts_returnsFalse() {
        XCTAssertFalse(AppointmentAvailabilityService.isBlackedOut(base, blackouts: []))
    }

    // MARK: - process convenience

    func test_process_appliesBufferAndBlackout() {
        let slots = [
            slot(startOffset: 0,    endOffset: 3600),   // 1h — in blackout
            slot(startOffset: 7200, endOffset: 10800),  // 1h — clear, will be buffered to 50min
        ]
        let blackouts = [blackout(label: "Morning", startOffset: -3600, endOffset: 4000)]
        let result = AppointmentAvailabilityService.process(
            slots: slots,
            bufferMinutes: 10,
            blackouts: blackouts
        )
        // First slot filtered by blackout; second slot buffered (50min usable)
        XCTAssertEqual(result.count, 1)
        let start = iso.date(from: result[0].start)!
        let end   = iso.date(from: result[0].end)!
        XCTAssertEqual(end.timeIntervalSince(start), 3000, accuracy: 1) // 50 min
    }
}
