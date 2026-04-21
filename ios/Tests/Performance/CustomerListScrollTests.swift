import XCTest

/// Scroll performance tests for `CustomerListView`.
///
/// Requires the app to be launched in harness mode (`-PerformanceHarness 1`).
///
/// TODO (follow-up): Wire `MockCustomerRepository(rowCount: 1000)` into `AppServices.swift`.
/// See `Tests/Performance/README.md` for the full wiring pattern.
final class CustomerListScrollTests: PerformanceTestCase {

    // MARK: - Tests

    /// Scrolls the customers list (1000 mock rows) and measures frame time.
    ///
    /// Phase 3 gate: p95 < 16.67 ms (60 fps minimum on iPhone SE).
    func testCustomerListScrollPerformance() throws {
        let customersTab = app.tabBars.buttons["Customers"]
        XCTAssertTrue(customersTab.waitForExistence(timeout: 5), "Customers tab not found")
        customersTab.tap()

        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 10), "Customers collection view not found")

        measureScroll(on: list)
    }
}
