import XCTest

/// Battery-drain benchmark over a scripted 2-minute exercise loop.
///
/// ## Device requirement
/// `UIDevice.current.batteryLevel` returns `1.0` on Simulator.
/// This test **skips automatically** unless `TEST_ENV=device` is set in the
/// environment. Run on a physical device with battery monitoring enabled:
///
/// ```bash
/// TEST_ENV=device xcodebuild test \
///   -project BizarreCRM.xcodeproj \
///   -scheme BizarreCRM \
///   -destination "platform=iOS,id=<UDID>" \
///   -only-testing:BizarreCRMUITests/BatteryBenchTests
/// ```
///
/// ## Output
/// Samples are written to `/tmp/battery-bench.csv` as:
///
/// ```
/// elapsed_s,battery_level,delta_from_start
/// 0.0,0.82,0.00
/// 15.0,0.82,-0.00
/// ...
/// ```
///
/// ## Interpretation
/// Battery level is a float in [0, 1]. Each 0.01 unit ≈ 1% charge.
/// A 2-minute exercise delta > 0.02 (2%) warrants investigation.
final class BatteryBenchTests: XCTestCase {

    // MARK: - Constants

    private static let exerciseDurationSeconds: TimeInterval = 120
    private static let sampleIntervalSeconds: TimeInterval = 15
    private static let csvPath = "/tmp/battery-bench.csv"

    // MARK: - Properties

    private var app: XCUIApplication!

    // MARK: - Setup

    override func setUpWithError() throws {
        continueAfterFailure = false

        // Skip on Simulator — battery API always returns 1.0.
        let isDevice = ProcessInfo.processInfo.environment["TEST_ENV"] == "device"
        try XCTSkipUnless(isDevice, "BatteryBenchTests requires TEST_ENV=device (physical device). Skipping on Simulator.")

        UIDevice.current.isBatteryMonitoringEnabled = true

        app = XCUIApplication()
        app.launchArguments += ["-PerformanceHarness", "1"]
        app.launch()
    }

    override func tearDownWithError() throws {
        UIDevice.current.isBatteryMonitoringEnabled = false
        app?.terminate()
        app = nil
    }

    // MARK: - Test

    /// Exercises the app for 2 minutes with scripted UI interactions and
    /// samples battery level every 15 seconds. Writes CSV to `/tmp/battery-bench.csv`.
    func testBatteryDrainDuringTypicalUse() throws {
        var samples: [(elapsedSeconds: TimeInterval, level: Float)] = []

        let startLevel = UIDevice.current.batteryLevel
        let startTime = Date()

        // Record initial sample.
        samples.append((0, startLevel))

        let deadline = startTime.addingTimeInterval(Self.exerciseDurationSeconds)
        var nextSampleTime = startTime.addingTimeInterval(Self.sampleIntervalSeconds)

        // Exercise loop: cycle through main tabs, scroll lists, open details.
        var iterationCount = 0

        while Date() < deadline {
            iterationCount += 1
            exerciseOneIteration()

            // Sample battery on schedule.
            let now = Date()
            if now >= nextSampleTime {
                let elapsed = now.timeIntervalSince(startTime)
                let level = UIDevice.current.batteryLevel
                samples.append((elapsed, level))
                nextSampleTime = nextSampleTime.addingTimeInterval(Self.sampleIntervalSeconds)
            }
        }

        // Final sample.
        let totalElapsed = Date().timeIntervalSince(startTime)
        let endLevel = UIDevice.current.batteryLevel
        samples.append((totalElapsed, endLevel))

        // Write CSV.
        writeCSV(samples: samples, startLevel: startLevel)

        // Report delta.
        let delta = startLevel - endLevel
        let deltaPercent = delta * 100

        XCTAssertGreaterThanOrEqual(
            startLevel,
            0,
            "Battery level unavailable — ensure the device has battery monitoring enabled"
        )

        // Soft assertion: log a warning if delta > 2% but don't fail the build,
        // since battery drain variance depends on charge level and thermals.
        if deltaPercent > 2.0 {
            XCTContext.runActivity(named: "Battery drain warning") { _ in
                XCTExpectFailure(
                    "Battery drain \(String(format: "%.2f", deltaPercent))% over 2 min exceeds 2% advisory threshold. Investigate rendering / network work on background threads.",
                    options: .nonStrict()
                )
            }
        }

        print("[BatteryBench] Total drain: \(String(format: "%.2f", deltaPercent))% over \(String(format: "%.0f", totalElapsed))s (\(iterationCount) iterations)")
        print("[BatteryBench] CSV written to \(Self.csvPath)")
    }

    // MARK: - Private

    /// Runs one iteration of the scripted UI exercise.
    ///
    /// Order: Tickets tab → scroll → open first row → back →
    ///        Customers tab → scroll → open first row → back →
    ///        Dashboard tab.
    private func exerciseOneIteration() {
        // Tickets
        tapTab("Tickets")
        scrollFirstList(swipes: 5)
        openFirstRow()
        navigateBack()

        // Customers
        tapTab("Customers")
        scrollFirstList(swipes: 5)
        openFirstRow()
        navigateBack()

        // Dashboard
        tapTab("Dashboard")
    }

    private func tapTab(_ label: String) {
        let tab = app.tabBars.buttons[label]
        guard tab.waitForExistence(timeout: 3) else { return }
        tab.tap()
    }

    private func scrollFirstList(swipes: Int) {
        let list = app.collectionViews.firstMatch
        guard list.waitForExistence(timeout: 5) else { return }
        for _ in 0 ..< swipes { list.swipeUp(velocity: .default) }
        for _ in 0 ..< swipes { list.swipeDown(velocity: .default) }
    }

    private func openFirstRow() {
        let firstCell = app.collectionViews.firstMatch.cells.firstMatch
        guard firstCell.waitForExistence(timeout: 3) else { return }
        firstCell.tap()
        // Brief pause to let the detail view render.
        Thread.sleep(forTimeInterval: 0.5)
    }

    private func navigateBack() {
        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.waitForExistence(timeout: 2) {
            backButton.tap()
        }
    }

    private func writeCSV(samples: [(elapsedSeconds: TimeInterval, level: Float)], startLevel: Float) {
        var lines = ["elapsed_s,battery_level,delta_from_start"]
        for (elapsed, level) in samples {
            let delta = level - startLevel
            lines.append(
                "\(String(format: "%.1f", elapsed)),\(String(format: "%.4f", level)),\(String(format: "%.4f", delta))"
            )
        }
        let content = lines.joined(separator: "\n")
        do {
            try content.write(toFile: Self.csvPath, atomically: true, encoding: .utf8)
        } catch {
            XCTFail("Failed to write battery CSV to \(Self.csvPath): \(error)")
        }
    }
}
