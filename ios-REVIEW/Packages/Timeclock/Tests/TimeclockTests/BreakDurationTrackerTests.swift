import XCTest
@testable import Timeclock

@MainActor
final class BreakDurationTrackerTests: XCTestCase {

    // MARK: - Initial state

    func test_initialState_isIdle() {
        let tracker = BreakDurationTracker()
        guard case .idle = tracker.breakState else {
            XCTFail("Expected .idle, got \(tracker.breakState)"); return
        }
        XCTAssertEqual(tracker.elapsedSeconds, 0)
    }

    // MARK: - breakDidStart

    func test_breakDidStart_setsOnBreakState() {
        let fixedNow = Date(timeIntervalSince1970: 1_745_000_000)
        let tracker = BreakDurationTracker(now: { fixedNow })
        let entry = makeBreakEntry(startAt: fixedNow.addingTimeInterval(-120))

        tracker.breakDidStart(entry)

        guard case .onBreak = tracker.breakState else {
            XCTFail("Expected .onBreak"); return
        }
    }

    func test_breakDidStart_computesElapsed() {
        let fixedNow = Date(timeIntervalSince1970: 1_745_000_000)
        let tracker = BreakDurationTracker(now: { fixedNow })
        let entry = makeBreakEntry(startAt: fixedNow.addingTimeInterval(-300)) // 5 min ago

        tracker.breakDidStart(entry)

        XCTAssertGreaterThanOrEqual(tracker.elapsedSeconds, 295)
        XCTAssertLessThanOrEqual(tracker.elapsedSeconds, 305)
    }

    // MARK: - breakDidEnd

    func test_breakDidEnd_resetsToIdle() {
        let fixedNow = Date(timeIntervalSince1970: 1_745_000_000)
        let tracker = BreakDurationTracker(now: { fixedNow })
        let entry = makeBreakEntry(startAt: fixedNow.addingTimeInterval(-60))
        tracker.breakDidStart(entry)

        tracker.breakDidEnd()

        guard case .idle = tracker.breakState else {
            XCTFail("Expected .idle"); return
        }
        XCTAssertEqual(tracker.elapsedSeconds, 0)
    }

    // MARK: - setFailed

    func test_setFailed_storeMessage() {
        let tracker = BreakDurationTracker()
        tracker.setFailed("Network error")
        guard case let .failed(msg) = tracker.breakState else {
            XCTFail("Expected .failed"); return
        }
        XCTAssertEqual(msg, "Network error")
    }

    // MARK: - tick

    func test_tick_doesNothing_whenIdle() {
        let tracker = BreakDurationTracker()
        tracker.tick()
        XCTAssertEqual(tracker.elapsedSeconds, 0)
    }

    func test_tick_updatesElapsed_whenOnBreak() {
        // Use two separate trackers with different fixed clocks to verify tick logic
        let base: TimeInterval = 1_745_000_000
        let startDate = Date(timeIntervalSince1970: base - 600) // 10 min before base

        // Tracker with base clock → elapsed ≈ 600
        let tracker1 = BreakDurationTracker(now: { Date(timeIntervalSince1970: base) })
        let entry = makeBreakEntry(startAt: startDate)
        tracker1.breakDidStart(entry)
        let elapsedBefore = tracker1.elapsedSeconds

        // Tracker with advanced clock → elapsed ≈ 660
        let tracker2 = BreakDurationTracker(now: { Date(timeIntervalSince1970: base + 60) })
        tracker2.breakDidStart(entry)
        tracker2.tick()
        let elapsedAfter = tracker2.elapsedSeconds

        XCTAssertGreaterThanOrEqual(elapsedBefore, 595)
        XCTAssertLessThanOrEqual(elapsedBefore, 605)
        XCTAssertGreaterThanOrEqual(elapsedAfter, 655)
        XCTAssertLessThanOrEqual(elapsedAfter, 665)
    }

    // MARK: - formatElapsed

    func test_formatElapsed_lessThan60s() {
        XCTAssertEqual(BreakDurationTracker.formatElapsed(0), "< 1m")
        XCTAssertEqual(BreakDurationTracker.formatElapsed(59), "< 1m")
    }

    func test_formatElapsed_minutes() {
        XCTAssertEqual(BreakDurationTracker.formatElapsed(60), "1m")
        XCTAssertEqual(BreakDurationTracker.formatElapsed(600), "10m")
        XCTAssertEqual(BreakDurationTracker.formatElapsed(3599), "59m")
    }

    func test_formatElapsed_hours() {
        XCTAssertEqual(BreakDurationTracker.formatElapsed(3600), "1h")
        XCTAssertEqual(BreakDurationTracker.formatElapsed(3660), "1h 1m")
        XCTAssertEqual(BreakDurationTracker.formatElapsed(7200), "2h")
    }

    // MARK: - Invalid ISO string

    func test_breakDidStart_invalidISO_elapsedZero() {
        let tracker = BreakDurationTracker()
        let entry = BreakEntry(id: 1, employeeId: 1, shiftId: 1,
                               startAt: "not-a-date", endAt: nil,
                               kind: .rest, paid: false)
        tracker.breakDidStart(entry)
        XCTAssertEqual(tracker.elapsedSeconds, 0)
    }

    // MARK: - Helpers

    private func makeBreakEntry(startAt: Date, paid: Bool = false) -> BreakEntry {
        BreakEntry(
            id: 1,
            employeeId: 1,
            shiftId: 1,
            startAt: ISO8601DateFormatter().string(from: startAt),
            endAt: nil,
            kind: .rest,
            paid: paid
        )
    }
}
