import XCTest

/// Scroll performance tests for `SmsThreadListView`.
///
/// Requires the app to be launched in harness mode (`-PerformanceHarness 1`).
///
/// Budget: `PerformanceBudget.scrollFrameP95Ms` (16.67 ms / 60 fps on iPhone SE).
///
/// TODO (follow-up): Wire `MockCommunicationsRepository(rowCount: 1000)` into `AppServices.swift`.
/// See `Tests/Performance/README.md` for the full wiring pattern.
final class SmsThreadListScrollTests: PerformanceTestCase {

    // MARK: - Tests

    /// Scrolls the SMS thread list (1000 mock rows) and measures frame time.
    ///
    /// §29 budget gate: p95 scroll deceleration < `PerformanceBudget.scrollFrameP95Ms` (16.67 ms).
    func testSmsThreadListScrollPerformance() throws {
        // SMS / Communications may be nested under a more label or a dedicated tab.
        // Try the tab bar button first; fall back to navigating through More if needed.
        let commsTab = app.tabBars.buttons.matching(
            NSPredicate(format: "label IN %@", ["Messages", "SMS", "Communications"])
        ).firstMatch

        if commsTab.waitForExistence(timeout: 3) {
            commsTab.tap()
        } else {
            // Some configurations put it under "More"
            let moreTab = app.tabBars.buttons["More"]
            assertExists(moreTab, timeout: 5, "Neither SMS nor More tab found")
            moreTab.tap()
            let smsCell = app.tables.cells.staticTexts.matching(
                NSPredicate(format: "label IN %@", ["Messages", "SMS", "Communications"])
            ).firstMatch
            assertExists(smsCell, timeout: 5, "SMS entry in More list not found")
            smsCell.tap()
        }

        let list = app.collectionViews.firstMatch
        assertExists(list, timeout: 10, "SMS thread collection view not found")

        measureScroll(on: list)
    }
}
