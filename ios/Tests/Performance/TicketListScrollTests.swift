import XCTest

/// Scroll performance tests for `TicketListView`.
///
/// Requires the app to be launched in harness mode (`-PerformanceHarness 1`).
///
/// TODO (follow-up): Wire `MockTicketRepository(rowCount: 1000)` into `AppServices.swift`
/// so the list actually renders 1000 deterministic rows during this test.
/// See `Tests/Performance/README.md` for the full wiring pattern.
final class TicketListScrollTests: PerformanceTestCase {

    // MARK: - Tests

    /// Scrolls the tickets list (1000 mock rows) and measures frame time.
    ///
    /// Phase 3 gate: p95 < 16.67 ms (60 fps minimum on iPhone SE).
    func testTicketListScrollPerformance() throws {
        // Navigate to the Tickets tab.
        let ticketsTab = app.tabBars.buttons["Tickets"]
        XCTAssertTrue(ticketsTab.waitForExistence(timeout: 5), "Tickets tab not found")
        ticketsTab.tap()

        // The list may be a UICollectionView (SwiftUI List) or a UITableView.
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 10), "Tickets collection view not found")

        measureScroll(on: list)
    }
}
