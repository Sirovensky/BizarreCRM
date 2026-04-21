import XCTest

/// Scroll performance tests for `InvoiceListView`.
///
/// Requires the app to be launched in harness mode (`-PerformanceHarness 1`).
///
/// TODO (follow-up): Wire `MockInvoiceRepository(rowCount: 1000)` into `AppServices.swift`.
/// See `Tests/Performance/README.md` for the full wiring pattern.
final class InvoiceListScrollTests: PerformanceTestCase {

    // MARK: - Tests

    /// Scrolls the invoices list (1000 mock rows) and measures frame time.
    ///
    /// Phase 3 gate: p95 < 16.67 ms (60 fps minimum on iPhone SE).
    func testInvoiceListScrollPerformance() throws {
        let invoicesTab = app.tabBars.buttons["Invoices"]
        XCTAssertTrue(invoicesTab.waitForExistence(timeout: 5), "Invoices tab not found")
        invoicesTab.tap()

        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 10), "Invoices collection view not found")

        measureScroll(on: list)
    }
}
