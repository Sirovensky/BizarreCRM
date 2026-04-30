import XCTest

/// Cold-start and warm-start benchmark tests.
///
/// ## Cold start (§29.1)
/// Terminates the app, then measures wall-clock time from launch to
/// the root tab bar becoming accessible. Asserts < `PerformanceBudget.coldStartMs`.
///
/// ## Warm start
/// Backgrounds the app (simulated via `XCUIDevice.shared.press(.home)`) and
/// brings it back. Asserts < `PerformanceBudget.warmStartMs`.
///
/// ## Device note
/// Run on a physical iPhone SE 3 for budget compliance.
/// Simulator numbers are informational only — cold-start on simulator
/// does not model real device NAND/RAM constraints.
final class ColdStartTests: XCTestCase {

    // MARK: - Properties

    private var app: XCUIApplication!

    // MARK: - Setup

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Cold start

    /// Measures cold-start time: terminate → launch → root tab bar visible.
    ///
    /// Budget: `PerformanceBudget.coldStartMs` (1500 ms on iPhone SE 3).
    func testColdStartTime() throws {
        // Ensure the app is not running so launch is truly cold.
        app.terminate()

        let start = Date()

        app.launch()

        // Wait for the root tab bar — the accessibility identifier is set on
        // the `TabView` in `RootView.swift` as `.accessibilityIdentifier("root.tabBar")`.
        let tabBar = app.tabBars["root.tabBar"]
        let appeared = tabBar.waitForExistence(timeout: 5)

        let elapsedMs = Date().timeIntervalSince(start) * 1000

        XCTAssertTrue(appeared, "Root tab bar did not appear within 5 s — cold-start gate cannot be measured")
        XCTAssertLessThan(
            elapsedMs,
            PerformanceBudget.coldStartMs,
            "Cold start \(String(format: "%.0f", elapsedMs)) ms exceeds budget of \(PerformanceBudget.coldStartMs) ms"
        )
    }

    /// Measures warm-start time: home → re-activate → root tab bar visible.
    ///
    /// Budget: `PerformanceBudget.warmStartMs` (250 ms).
    func testWarmStartTime() throws {
        // Launch once so the process is warmed.
        app.launch()

        let tabBar = app.tabBars["root.tabBar"]
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "App did not reach home screen before warm-start test")

        // Press home to background the app.
        XCUIDevice.shared.press(.home)

        // Brief pause to ensure the system has backgrounded it.
        // (Not a sleep-in-a-loop — one fixed wait for OS state transition.)
        Thread.sleep(forTimeInterval: 0.5)

        let start = Date()

        // Re-activate the app by launching it again (XCUITest re-activates a backgrounded app).
        app.activate()

        let reappeared = tabBar.waitForExistence(timeout: 3)
        let elapsedMs = Date().timeIntervalSince(start) * 1000

        XCTAssertTrue(reappeared, "Root tab bar did not reappear after warm launch within 3 s")
        XCTAssertLessThan(
            elapsedMs,
            PerformanceBudget.warmStartMs,
            "Warm start \(String(format: "%.0f", elapsedMs)) ms exceeds budget of \(PerformanceBudget.warmStartMs) ms"
        )
    }

    // MARK: - XCTMetric variant (baseline-tracked)

    /// Budget-tracked cold-start using `XCTClockMetric` so Xcode stores a
    /// performance baseline in the `.xcresult` bundle for PR diff checks.
    func testColdStartMeasured() throws {
        let measureOptions = XCTMeasureOptions()
        measureOptions.iterationCount = 3

        measure(metrics: [XCTClockMetric()], options: measureOptions) {
            app.terminate()
            app.launch()
            let tabBar = app.tabBars["root.tabBar"]
            _ = tabBar.waitForExistence(timeout: 5)
            // Termination happens in the next iteration's setup above.
        }
    }

    // MARK: - §31.5 Launch time — XCTApplicationLaunchMetric budget enforcement

    /// Launch-time benchmark using Apple's purpose-built
    /// `XCTApplicationLaunchMetric`. Unlike `XCTClockMetric`, this metric
    /// records process spawn → first-frame timing as reported by the OS,
    /// which is what App Store Connect / MetricKit also report — so the
    /// baseline aligns with production telemetry.
    ///
    /// The metric stores a per-device baseline in the `.xcresult` bundle.
    /// Regressions surface in CI as a PR diff against the stored baseline.
    func testLaunchTimeApplicationMetric() throws {
        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            app.launch()
            // Don't assert visibility here — `XCTApplicationLaunchMetric`
            // already brackets process-spawn → first-frame internally.
            // Adding work inside the closure pollutes the measurement.
        }
    }
}
