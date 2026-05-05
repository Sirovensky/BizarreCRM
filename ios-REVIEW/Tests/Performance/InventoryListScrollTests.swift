import XCTest

/// Scroll performance tests for `InventoryListView`.
///
/// Requires the app to be launched in harness mode (`-PerformanceHarness 1`).
///
/// Budget: `PerformanceBudget.scrollFrameP95Ms` (16.67 ms / 60 fps on iPhone SE).
///
/// TODO (follow-up): Wire `MockInventoryRepository(rowCount: 1000)` into `AppServices.swift`.
/// See `Tests/Performance/README.md` for the full wiring pattern.
final class InventoryListScrollTests: PerformanceTestCase {

    // MARK: - Tests

    /// Scrolls the inventory list (1000 mock rows) and measures frame time.
    ///
    /// §29 budget gate: p95 scroll deceleration < `PerformanceBudget.scrollFrameP95Ms` (16.67 ms).
    func testInventoryListScrollPerformance() throws {
        let inventoryTab = app.tabBars.buttons["Inventory"]
        assertExists(inventoryTab, timeout: 5, "Inventory tab not found")
        inventoryTab.tap()

        let list = app.collectionViews.firstMatch
        assertExists(list, timeout: 10, "Inventory collection view not found")

        measureScroll(on: list)
    }
}
