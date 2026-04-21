import XCTest

/// Base class for scroll performance tests.
///
/// Uses `XCTOSSignpostMetric` + `XCTClockMetric` to capture per-frame timing.
/// All scroll tests inherit from this class and call `measureScroll(on:swipeCount:)`.
///
/// ## Harness mode
/// The app must be launched with `-PerformanceHarness 1` in launch arguments.
/// The host app should detect this flag in `AppServices.swift` and swap real
/// repositories for mock implementations returning 1000 deterministic rows.
/// See `Tests/Performance/README.md` for the wiring TODO.
class PerformanceTestCase: XCTestCase {

    // MARK: - Properties

    var app: XCUIApplication!

    // MARK: - Setup / Teardown

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-PerformanceHarness", "1"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Helpers

    /// Measures mean + p95 + max frame time while scrolling a list from top to bottom and back.
    ///
    /// - Parameters:
    ///   - element: The scrollable `XCUIElement` to exercise (typically `app.collectionViews.firstMatch`
    ///              or `app.tables.firstMatch`).
    ///   - swipeCount: Number of swipe gestures in each direction. Default 20.
    ///
    /// Pass criteria (Phase 3 gate): p95 frame time < 16.67 ms (≥ 60 fps).
    /// On ProMotion devices the target is < 8.33 ms (≥ 120 fps).
    func measureScroll(on element: XCUIElement, swipeCount: Int = 20) {
        let measureOptions = XCTMeasureOptions()
        measureOptions.iterationCount = 3

        measure(
            metrics: [
                XCTOSSignpostMetric.scrollDecelerationMetric,
                XCTOSSignpostMetric.navigationTransitionMetric,
                XCTClockMetric()
            ],
            options: measureOptions
        ) {
            for _ in 0 ..< swipeCount {
                element.swipeUp(velocity: .fast)
            }
            for _ in 0 ..< swipeCount {
                element.swipeDown(velocity: .fast)
            }
        }
    }
}
