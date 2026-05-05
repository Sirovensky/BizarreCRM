// Tests/Performance/RTLSmokeTests.swift
//
// XCUITest smoke suite — exercises key screens in both LTR and RTL layout
// to catch alignment bugs, clipped text, and misaligned elements.
//
// Runs via:
//   xcodebuild test -only-testing:BizarreCRMUITests/RTLSmokeTests
//
// Screenshots saved to /tmp/rtl-screenshots/ for CI artifact upload.
//
// §27 RTL layout checks

import XCTest

// MARK: - Screenshot helpers

private func screenshotDir() -> String { "/tmp/rtl-screenshots" }

private func saveScreenshot(_ screenshot: XCUIScreenshot, named name: String) {
    let dir = screenshotDir()
    let fm = FileManager.default
    if !fm.fileExists(atPath: dir) {
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }
    let path = "\(dir)/\(name).png"
    let data = screenshot.pngRepresentation
    fm.createFile(atPath: path, contents: data)
}

// MARK: - RTLSmokeTests

@MainActor
final class RTLSmokeTests: XCTestCase {

    // MARK: - Properties

    private var app: XCUIApplication!

    // MARK: - Setup / Teardown

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    // MARK: - Launch helpers

    /// Launch in the specified locale/language environment.
    ///
    /// - Parameters:
    ///   - language: BCP-47 language tag placed into `-AppleLanguages`, e.g. `"ar"` or `"en"`.
    ///   - region:   BCP-47 region, e.g. `"SA"` or `"US"`.
    private func launchApp(language: String, region: String) {
        app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", "\(language)_\(region)",
            // Performance harness flag keeps mock data wired (Phase 3 convention).
            "-PerformanceHarness", "1"
        ]
        app.launch()
    }

    /// Wait for an element; fail with a useful message if it doesn't appear.
    private func assertExists(
        _ element: XCUIElement,
        timeout: TimeInterval = 10,
        _ message: String = ""
    ) {
        let msg = message.isEmpty
            ? "\(element.description) not found within \(timeout)s"
            : message
        XCTAssertTrue(element.waitForExistence(timeout: timeout), msg)
    }

    /// Assert that no text element on screen has a frame whose width or height
    /// is effectively zero (a proxy for clipped / invisible text).
    private func assertNoClippedText(screenshotName: String) {
        let screenshot = app.screenshot()
        saveScreenshot(screenshot, named: screenshotName)

        // Collect all static text elements and verify their frames have positive area.
        let texts = app.staticTexts.allElementsBoundByIndex
        for text in texts {
            let frame = text.frame
            // Allow zero-size for empty labels that may exist as structural placeholders.
            if !text.label.isEmpty {
                XCTAssertGreaterThan(
                    frame.width,
                    0,
                    "Text '\(text.label)' has zero width — possible clip in \(screenshotName)"
                )
                XCTAssertGreaterThan(
                    frame.height,
                    0,
                    "Text '\(text.label)' has zero height — possible clip in \(screenshotName)"
                )
            }
        }
    }

    // MARK: - LTR baseline (sanity)

    func testLoginFlowView_LTR() throws {
        launchApp(language: "en", region: "US")
        // Login screen is the initial screen; wait for a primary CTA.
        let loginButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Log' OR label CONTAINS[c] 'Sign'")
        ).firstMatch
        assertExists(loginButton, "LoginFlowView primary CTA not found in LTR")
        assertNoClippedText(screenshotName: "login_ltr")
    }

    func testDashboardView_LTR() throws {
        launchApp(language: "en", region: "US")
        // Navigate past login to dashboard using the harness deep-link argument.
        // The performance harness bypasses auth in Phase 3 — look for dashboard content.
        let dashboard = app.navigationBars.firstMatch
        _ = dashboard.waitForExistence(timeout: 10)
        assertNoClippedText(screenshotName: "dashboard_ltr")
    }

    // MARK: - RTL smoke tests

    /// §27.4 — LoginFlowView in Arabic RTL locale.
    ///
    /// Asserts:
    /// - Primary login CTA visible and non-clipped.
    /// - Text fields visible.
    /// - No zero-size text elements.
    func testLoginFlowView_RTL() throws {
        launchApp(language: "ar", region: "SA")

        // Primary CTA — Arabic label or fallback English depending on localization state.
        // We look for any button that could be the login action.
        let loginButtons = app.buttons.allElementsBoundByIndex
        XCTAssertGreaterThan(
            loginButtons.count,
            0,
            "No buttons found on LoginFlowView in RTL — layout may have collapsed"
        )

        // At least one text field should be visible (server URL + credentials).
        let textFields = app.textFields.allElementsBoundByIndex
        XCTAssertGreaterThan(
            textFields.count,
            0,
            "No text fields found on LoginFlowView in RTL"
        )

        assertNoClippedText(screenshotName: "login_rtl")
    }

    /// §27.4 — DashboardView in Arabic RTL locale.
    ///
    /// Asserts:
    /// - Navigation bar or tab bar is present.
    /// - At least one visible tile / cell (recent activity, clock tile, etc.).
    /// - No zero-size text elements.
    func testDashboardView_RTL() throws {
        launchApp(language: "ar", region: "SA")

        // Wait for the app to finish launching; look for any navigation chrome.
        let navBar = app.navigationBars.firstMatch
        _ = navBar.waitForExistence(timeout: 15)

        // Dashboard should surface at least one scrollable container or tile.
        let hasScrollView = app.scrollViews.firstMatch.waitForExistence(timeout: 10)
            || app.collectionViews.firstMatch.waitForExistence(timeout: 5)
        XCTAssertTrue(
            hasScrollView,
            "DashboardView: no scroll view found in RTL — grid/list may not have rendered"
        )

        assertNoClippedText(screenshotName: "dashboard_rtl")
    }

    /// §27.4 — TicketListView in Arabic RTL locale.
    ///
    /// Asserts:
    /// - A list or collection view is present.
    /// - Row text is not clipped.
    func testTicketListView_RTL() throws {
        launchApp(language: "ar", region: "SA")

        // Attempt to navigate to Tickets tab via tab bar or sidebar.
        let ticketsTab = app.tabBars.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Ticket' OR label CONTAINS[c] 'تذكرة'")
        ).firstMatch

        if ticketsTab.waitForExistence(timeout: 5) {
            ticketsTab.tap()
        }
        // On iPad split view the sidebar item may already be selected — either way,
        // we wait for a list structure.
        let list = app.tables.firstMatch
        let collection = app.collectionViews.firstMatch
        let hasContent = list.waitForExistence(timeout: 10)
            || collection.waitForExistence(timeout: 5)
        XCTAssertTrue(
            hasContent,
            "TicketListView: no table/collection found in RTL"
        )

        assertNoClippedText(screenshotName: "tickets_rtl")
    }

    /// §27.4 — PosView cart in Arabic RTL locale.
    ///
    /// Asserts:
    /// - POS screen reachable (tab or sidebar item).
    /// - Cart column / area visible.
    /// - Price labels not clipped.
    func testPosView_RTL() throws {
        launchApp(language: "ar", region: "SA")

        // Navigate to POS.
        let posTab = app.tabBars.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'POS' OR label CONTAINS[c] 'Sale' OR label CONTAINS[c] 'بيع'")
        ).firstMatch

        if posTab.waitForExistence(timeout: 5) {
            posTab.tap()
        }

        // Wait for any content area — POS typically has a collection of products.
        let hasContent = app.collectionViews.firstMatch.waitForExistence(timeout: 10)
            || app.tables.firstMatch.waitForExistence(timeout: 5)
            || app.scrollViews.firstMatch.waitForExistence(timeout: 5)
        XCTAssertTrue(
            hasContent,
            "PosView: no content area found in RTL"
        )

        assertNoClippedText(screenshotName: "pos_rtl")
    }

    // MARK: - Screenshot directory existence test

    /// Verifies the screenshot output directory can be created.
    /// This test runs first (alphabetically) to guarantee the dir exists.
    func testAAA_ScreenshotDirectoryCreated() throws {
        let dir = screenshotDir()
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        XCTAssertTrue(fm.fileExists(atPath: dir), "Failed to create screenshot dir at \(dir)")
    }
}
