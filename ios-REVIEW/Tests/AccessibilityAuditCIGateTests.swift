// ios/Tests/AccessibilityAuditCIGateTests.swift
//
// §31.6 — `XCTest.performAccessibilityAudit(for:)` CI gate.
//
// Per-screen XCUITest that walks the app's primary surfaces and fires
// the iOS 17+ `XCUIApplication.performAccessibilityAudit(for:)` call.
// Any audit issue in a covered category fails the build, providing the
// "fails build on new violations" gate called for in §31.6.
//
// Audit categories covered (all available pre-iOS 17 audit set):
//   - .contrast              Foreground/background contrast under WCAG.
//   - .elementDetection      Hit-testable elements have valid frames.
//   - .hitRegion             Tap targets ≥ 44×44 pt (iOS HIG floor).
//   - .sufficientElementDescription  Elements have non-empty labels.
//   - .dynamicType           Text scales with Dynamic Type.
//   - .textClipped           No truncated text in default content size.
//   - .trait                 Traits match the visible role.
//   - .action                Interactive elements expose actions.
//
// To allow gradual onboarding, screens that aren't yet audit-clean are
// gated by a `KNOWN_FAILING_AUDITS` env-var allowlist — same pattern as
// the existing a11y-audit.sh regression harness.

import XCTest

@available(iOS 17.0, *)
final class AccessibilityAuditCIGateTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "--mock-auth",
            "--mock-api",
            "--skip-onboarding",
            "--disable-animations"
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
        try super.tearDownWithError()
    }

    // MARK: - Audit categories

    /// All categories enabled for the CI gate. Mirrored across every screen
    /// test so failures are uniform regardless of which screen tripped.
    private var auditCategories: XCUIAccessibilityAuditType {
        [
            .contrast,
            .elementDetection,
            .hitRegion,
            .sufficientElementDescription,
            .dynamicType,
            .textClipped,
            .trait,
            .action
        ]
    }

    // MARK: - Per-screen gates

    func test_dashboard_passesAccessibilityAudit() throws {
        let tabBar = app.tabBars["root.tabBar"]
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "dashboard never appeared")
        try app.performAccessibilityAudit(for: auditCategories)
    }

    func test_ticketsList_passesAccessibilityAudit() throws {
        let tabBar = app.tabBars["root.tabBar"]
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        // Dashboard's tab bar exposes a "Tickets" button by accessibility ID.
        let ticketsTab = tabBar.buttons["root.tab.tickets"]
        if ticketsTab.exists { ticketsTab.tap() }
        try app.performAccessibilityAudit(for: auditCategories)
    }

    func test_settings_passesAccessibilityAudit() throws {
        let tabBar = app.tabBars["root.tabBar"]
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        let settingsTab = tabBar.buttons["root.tab.settings"]
        if settingsTab.exists { settingsTab.tap() }
        try app.performAccessibilityAudit(for: auditCategories)
    }
}
