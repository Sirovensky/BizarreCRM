import XCTest

/// List-render time benchmarks.
///
/// Measures time from tab-select to first row visible (via accessibility identifier
/// `list.ready` set on the first cell when the list is populated).
///
/// ## Harness mode
/// App must be launched with `-PerformanceHarness 1`.
/// Wire-up of `MockRepository` → `list.ready` identifier is a TODO per Phase 3.
/// See `Tests/Performance/README.md`.
///
/// ## Budget
/// `PerformanceBudget.listRenderMs` = 500 ms.
final class ListRenderTests: XCTestCase {

    // MARK: - Properties

    private var app: XCUIApplication!

    // MARK: - Setup

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-PerformanceHarness", "1"]
        app.launch()

        // Ensure app is on the home tab before each test.
        let tab = app.tabBars.buttons["Dashboard"]
        _ = tab.waitForExistence(timeout: 10)
        tab.tap()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Tests

    /// Measures Tickets list render time from tab tap → first row visible.
    ///
    /// §29 budget gate: < `PerformanceBudget.listRenderMs` (500 ms).
    func testTicketsListRenderTime() throws {
        try measureListRender(tabName: "Tickets")
    }

    /// Measures Customers list render time from tab tap → first row visible.
    ///
    /// §29 budget gate: < `PerformanceBudget.listRenderMs` (500 ms).
    func testCustomersListRenderTime() throws {
        try measureListRender(tabName: "Customers")
    }

    /// Measures Inventory list render time from tab tap → first row visible.
    ///
    /// §29 budget gate: < `PerformanceBudget.listRenderMs` (500 ms).
    func testInventoryListRenderTime() throws {
        try measureListRender(tabName: "Inventory")
    }

    // MARK: - XCTMetric baseline variant

    /// Budget-tracked tickets list render using `XCTClockMetric` for xcresult baselines.
    func testTicketsListRenderMeasured() throws {
        let options = XCTMeasureOptions()
        options.iterationCount = 3

        let ticketsTab = app.tabBars.buttons["Tickets"]
        XCTAssertTrue(ticketsTab.waitForExistence(timeout: 5), "Tickets tab not found")

        measure(metrics: [XCTClockMetric()], options: options) {
            // Navigate away then back so each iteration starts fresh.
            app.tabBars.buttons["Dashboard"].tap()
            ticketsTab.tap()
            _ = app.staticTexts["list.ready"].waitForExistence(
                timeout: PerformanceBudget.listRenderMs / 1000.0 + 1
            )
        }
    }

    // MARK: - Private

    /// Taps `tabName` and measures time until `staticTexts["list.ready"]` appears.
    ///
    /// Asserts the elapsed time is under `PerformanceBudget.listRenderMs`.
    ///
    /// - Note: `list.ready` is an accessibility identifier placed on the first visible
    ///   cell by the list view once its data source is populated. See Phase 3 wiring TODO.
    private func measureListRender(tabName: String) throws {
        let tab = app.tabBars.buttons[tabName]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "\(tabName) tab not found")

        let start = Date()
        tab.tap()

        let readyMarker = app.staticTexts["list.ready"]
        let budgetSeconds = PerformanceBudget.listRenderMs / 1000.0
        // Give an extra second headroom for the waitForExistence call itself.
        let appeared = readyMarker.waitForExistence(timeout: budgetSeconds + 1)

        let elapsedMs = Date().timeIntervalSince(start) * 1000

        // If the ready marker isn't wired yet, fall back to first collection view cell.
        if !appeared {
            let list = app.collectionViews.firstMatch
            XCTAssertTrue(
                list.waitForExistence(timeout: 5),
                "\(tabName) list did not appear — harness wiring may be incomplete"
            )
            // Measure with the fallback element.
            let fallbackElapsedMs = Date().timeIntervalSince(start) * 1000
            XCTAssertLessThan(
                fallbackElapsedMs,
                PerformanceBudget.listRenderMs,
                "\(tabName) list render \(String(format: "%.0f", fallbackElapsedMs)) ms exceeds budget of \(PerformanceBudget.listRenderMs) ms (fallback measurement)"
            )
            return
        }

        XCTAssertLessThan(
            elapsedMs,
            PerformanceBudget.listRenderMs,
            "\(tabName) list render \(String(format: "%.0f", elapsedMs)) ms exceeds budget of \(PerformanceBudget.listRenderMs) ms"
        )
    }
}
