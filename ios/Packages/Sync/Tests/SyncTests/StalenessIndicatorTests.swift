import XCTest
@testable import Sync

/// Tests use `StalenessLogic` (pure value type, no MainActor) for all
/// business-logic coverage. The SwiftUI view is tested via snapshot / preview
/// in integration.
final class StalenessIndicatorTests: XCTestCase {

    // MARK: - Label tests

    func test_label_neverSynced() {
        let sut = StalenessLogic(lastSyncedAt: nil)
        XCTAssertEqual(sut.label, "Never synced")
    }

    func test_label_justNow_under60s() {
        let now = Date()
        let sut = StalenessLogic(lastSyncedAt: now.addingTimeInterval(-30), now: now)
        XCTAssertEqual(sut.label, "Just now")
    }

    func test_label_minutes_between1and60() {
        let now = Date()
        let sut = StalenessLogic(lastSyncedAt: now.addingTimeInterval(-600), now: now)
        XCTAssertEqual(sut.label, "10 min ago")
    }

    func test_label_1minuteAgo() {
        let now = Date()
        let sut = StalenessLogic(lastSyncedAt: now.addingTimeInterval(-65), now: now)
        XCTAssertEqual(sut.label, "1 min ago")
    }

    func test_label_hours_over60min() {
        let now = Date()
        let sut = StalenessLogic(lastSyncedAt: now.addingTimeInterval(-7_200), now: now)
        XCTAssertEqual(sut.label, "2 hr ago")
    }

    func test_label_1hourAgo() {
        let now = Date()
        let sut = StalenessLogic(lastSyncedAt: now.addingTimeInterval(-3_601), now: now)
        XCTAssertEqual(sut.label, "1 hr ago")
    }

    // MARK: - Staleness level tests

    func test_stalenessLevel_never_returnsNever() {
        let sut = StalenessLogic(lastSyncedAt: nil)
        XCTAssertEqual(sut.stalenessLevel, .never)
    }

    func test_stalenessLevel_fresh_under1hour() {
        let now = Date()
        let sut = StalenessLogic(lastSyncedAt: now.addingTimeInterval(-1_800), now: now)
        XCTAssertEqual(sut.stalenessLevel, .fresh)
    }

    func test_stalenessLevel_fresh_justNow() {
        let now = Date()
        let sut = StalenessLogic(lastSyncedAt: now.addingTimeInterval(-5), now: now)
        XCTAssertEqual(sut.stalenessLevel, .fresh)
    }

    func test_stalenessLevel_warning_between1and4hours() {
        let now = Date()
        let sut = StalenessLogic(lastSyncedAt: now.addingTimeInterval(-5_400), now: now)
        XCTAssertEqual(sut.stalenessLevel, .warning)
    }

    func test_stalenessLevel_stale_over4hours() {
        let now = Date()
        let sut = StalenessLogic(lastSyncedAt: now.addingTimeInterval(-20_000), now: now)
        XCTAssertEqual(sut.stalenessLevel, .stale)
    }

    // MARK: - A11y label tests

    func test_a11yLabel_neverSynced() {
        let sut = StalenessLogic(lastSyncedAt: nil)
        XCTAssertEqual(sut.a11yLabel, "Data was never synced")
    }

    func test_a11yLabel_justNow() {
        let now = Date()
        let sut = StalenessLogic(lastSyncedAt: now.addingTimeInterval(-30), now: now)
        XCTAssertEqual(sut.a11yLabel, "Data last updated just now")
    }

    func test_a11yLabel_minutesAgo() {
        let now = Date()
        let sut = StalenessLogic(lastSyncedAt: now.addingTimeInterval(-120), now: now)
        XCTAssertEqual(sut.a11yLabel, "Data last updated 2 minutes ago")
    }

    func test_a11yLabel_1MinuteAgo_singular() {
        let now = Date()
        let sut = StalenessLogic(lastSyncedAt: now.addingTimeInterval(-65), now: now)
        XCTAssertEqual(sut.a11yLabel, "Data last updated 1 minute ago")
    }

    func test_a11yLabel_hoursAgo() {
        let now = Date()
        let sut = StalenessLogic(lastSyncedAt: now.addingTimeInterval(-7_200), now: now)
        XCTAssertEqual(sut.a11yLabel, "Data last updated 2 hours ago")
    }

    func test_a11yLabel_1HourAgo_singular() {
        let now = Date()
        let sut = StalenessLogic(lastSyncedAt: now.addingTimeInterval(-3_601), now: now)
        XCTAssertEqual(sut.a11yLabel, "Data last updated 1 hour ago")
    }

    // MARK: - Boundary tests

    func test_exactlyAt1Hour_minus1s_isFresh() {
        let now = Date()
        let sut = StalenessLogic(lastSyncedAt: now.addingTimeInterval(-3_599), now: now)
        XCTAssertEqual(sut.stalenessLevel, .fresh)
    }

    func test_exactly1Hour_isWarning() {
        let now = Date()
        let sut = StalenessLogic(lastSyncedAt: now.addingTimeInterval(-3_600), now: now)
        XCTAssertEqual(sut.stalenessLevel, .warning)
    }

    func test_exactlyAt4Hours_isStale() {
        let now = Date()
        let sut = StalenessLogic(lastSyncedAt: now.addingTimeInterval(-14_400), now: now)
        XCTAssertEqual(sut.stalenessLevel, .stale)
    }

    func test_justUnder4Hours_isWarning() {
        let now = Date()
        let sut = StalenessLogic(lastSyncedAt: now.addingTimeInterval(-14_399), now: now)
        XCTAssertEqual(sut.stalenessLevel, .warning)
    }
}
