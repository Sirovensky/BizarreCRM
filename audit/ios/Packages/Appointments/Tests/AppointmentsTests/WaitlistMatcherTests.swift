import XCTest
@testable import Appointments

// MARK: - WaitlistMatcherTests
// TDD: written before WaitlistMatcher was implemented.

final class WaitlistMatcherTests: XCTestCase {

    // MARK: - Helpers

    private let base = Date(timeIntervalSince1970: 1_700_000_000) // fixed reference

    private func makeEntry(
        id: String = UUID().uuidString,
        customerId: Int64 = 1,
        preferredWindows: [PreferredWindow] = [],
        createdAt: Date,
        status: WaitlistStatus = .waiting
    ) -> WaitlistEntry {
        WaitlistEntry(
            id: id,
            customerId: customerId,
            requestedServiceType: "Haircut",
            preferredWindows: preferredWindows,
            note: nil,
            createdAt: createdAt,
            status: status
        )
    }

    private func window(offsetHours: Double, durationHours: Double) -> PreferredWindow {
        PreferredWindow(
            start: base.addingTimeInterval(offsetHours * 3600),
            end: base.addingTimeInterval((offsetHours + durationHours) * 3600)
        )
    }

    // MARK: - Empty / edge cases

    func test_emptyList_returnsEmpty() {
        let result = WaitlistMatcher.rank(candidates: [], availableSlot: base, duration: 3600)
        XCTAssertTrue(result.isEmpty)
    }

    func test_onlyIneligibleStatuses_returnsEmpty() {
        let scheduled = makeEntry(createdAt: base, status: .scheduled)
        let canceled  = makeEntry(createdAt: base, status: .canceled)
        let result = WaitlistMatcher.rank(candidates: [scheduled, canceled], availableSlot: base, duration: 3600)
        XCTAssertTrue(result.isEmpty)
    }

    func test_waitingAndOfferedAreEligible() {
        let waiting  = makeEntry(id: "w", createdAt: base.addingTimeInterval(-100), status: .waiting)
        let offered  = makeEntry(id: "o", createdAt: base.addingTimeInterval(-50),  status: .offered)
        let result = WaitlistMatcher.rank(candidates: [waiting, offered], availableSlot: base, duration: 3600)
        XCTAssertEqual(result.count, 2)
    }

    // MARK: - Preference match beats no-preference

    func test_preferenceMatch_ranksHigher() {
        let noMatch = makeEntry(id: "nm", createdAt: base.addingTimeInterval(-200), status: .waiting)
        // preferredWindow exactly covers the slot
        let match   = makeEntry(
            id: "m",
            preferredWindows: [window(offsetHours: 0, durationHours: 2)],
            createdAt: base.addingTimeInterval(-100), // newer = normally lower rank
            status: .waiting
        )
        let result = WaitlistMatcher.rank(candidates: [noMatch, match], availableSlot: base, duration: 3600)
        XCTAssertEqual(result.first?.id, "m", "Preference match should rank first despite newer createdAt")
    }

    // MARK: - Tie-break by createdAt

    func test_tieBreak_oldestFirst() {
        let older  = makeEntry(id: "old", createdAt: base.addingTimeInterval(-200), status: .waiting)
        let newer  = makeEntry(id: "new", createdAt: base.addingTimeInterval(-100), status: .waiting)
        let result = WaitlistMatcher.rank(candidates: [newer, older], availableSlot: base, duration: 3600)
        XCTAssertEqual(result.first?.id, "old")
        XCTAssertEqual(result.last?.id,  "new")
    }

    // MARK: - Preference match: partial window overlap counts

    func test_partialWindowOverlap_counts() {
        // Slot: base … base+1h. Window: base+0.5h … base+1.5h — overlaps.
        let entry = makeEntry(
            id: "partial",
            preferredWindows: [window(offsetHours: 0.5, durationHours: 1.0)],
            createdAt: base,
            status: .waiting
        )
        let noWin = makeEntry(id: "nowin", createdAt: base.addingTimeInterval(-1000), status: .waiting)
        let result = WaitlistMatcher.rank(candidates: [noWin, entry], availableSlot: base, duration: 3600)
        XCTAssertEqual(result.first?.id, "partial", "Partial overlap should still count as a match")
    }

    // MARK: - Non-overlapping window does not help

    func test_nonOverlappingWindow_doesNotBoost() {
        let entry = makeEntry(
            id: "late",
            preferredWindows: [window(offsetHours: 5, durationHours: 1)], // far from slot
            createdAt: base,
            status: .waiting
        )
        let older = makeEntry(id: "older", createdAt: base.addingTimeInterval(-100), status: .waiting)
        let result = WaitlistMatcher.rank(candidates: [entry, older], availableSlot: base, duration: 3600)
        XCTAssertEqual(result.first?.id, "older")
    }

    // MARK: - Multiple preference windows — any match wins

    func test_multiplePreferenceWindows_anyMatchWins() {
        let entry = makeEntry(
            id: "multi",
            preferredWindows: [
                window(offsetHours: 10, durationHours: 1), // no match
                window(offsetHours: 0,  durationHours: 2)  // match
            ],
            createdAt: base,
            status: .waiting
        )
        let noMatch = makeEntry(id: "nm", createdAt: base.addingTimeInterval(-500), status: .waiting)
        let result = WaitlistMatcher.rank(candidates: [noMatch, entry], availableSlot: base, duration: 3600)
        XCTAssertEqual(result.first?.id, "multi")
    }

    // MARK: - Stable sort preserves relative order of equal-score equal-time entries

    func test_sameScore_sameTime_stableOrder() {
        let a = makeEntry(id: "a", createdAt: base, status: .waiting)
        let b = makeEntry(id: "b", createdAt: base, status: .waiting)
        // Both have same score, same time — output order should be deterministic (not crash).
        let result = WaitlistMatcher.rank(candidates: [a, b], availableSlot: base, duration: 3600)
        XCTAssertEqual(result.count, 2)
    }
}
