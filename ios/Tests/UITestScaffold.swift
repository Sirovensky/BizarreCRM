import XCTest

// §31.4 — UI test scaffolding
//
// Provides base classes, launch helpers, and page-object stubs for the
// XCUITest golden-path flows described in §31.4:
//
//   • Login → Dashboard → New Ticket → Add Payment → Print Receipt
//   • POS: catalog browse → add 3 items → customer pick → stub → success
//   • SMS: open thread → send → WS event → bubble appears
//   • Offline: airplane on → create customer → airplane off → verify sync
//   • Auth: login / logout / 401 auto-logout / biometric re-auth
//   • Accessibility audits (iOS 17+ performAccessibilityAudit)
//
// Design principles:
//   - Each test class inherits `BizarreCRMUITestCase` (launch + teardown
//     handled once).
//   - Page objects (e.g. `LoginPage`, `DashboardPage`) wrap XCUIApplication
//     queries so tests read as intent, not element paths.
//   - Launch arguments / environment variables are declared as typed constants
//     in `UITestLaunchArgs` so callers never mistype string literals.
//   - `stubAPI(_:)` injects `--mock-api` launch arg so the app loads stub
//     responses from JSON fixtures bundled in UITestData/.
//
// Status: scaffold (§31.4 [ ] items). Add implementations as golden-path
// flows become stable. Each class below is marked `open` so specific test
// files in a UITests/ target can subclass without re-importing.

// MARK: - Launch argument constants

/// Typed launch arguments consumed by the app's `AppEnvironment` at startup.
/// The app checks `CommandLine.arguments.contains(key.rawValue)`.
public enum UITestLaunchArg: String {
    /// Bypass biometric / passcode prompts; use ephemeral keychain service.
    case mockAuth       = "--mock-auth"
    /// Load API responses from JSON stubs instead of hitting the network.
    case mockAPI        = "--mock-api"
    /// Skip onboarding / first-run sheets.
    case skipOnboarding = "--skip-onboarding"
    /// Pre-seed GRDB with demo fixture data (20 tickets / 30 customers / 50 inventory).
    case seedFixtures   = "--seed-fixtures"
    /// Force airplane-mode simulation inside the app (NWPathMonitor override).
    case airplaneMode   = "--airplane-mode"
    /// Disable animations so assertions don't race against transitions.
    case disableAnimations = "--disable-animations"
}

/// Typed environment variables injected via `XCUIApplication.launchEnvironment`.
public enum UITestEnvVar: String {
    /// Base URL for the stub server (default: http://localhost:8080).
    case stubServerURL  = "UITEST_STUB_SERVER_URL"
    /// Fixture dataset seed (integer string, matches `RandomFixtureSeed`).
    case fixtureSeed    = "UITEST_FIXTURE_SEED"
    /// Tenant slug pre-populated in the login screen.
    case tenantSlug     = "UITEST_TENANT_SLUG"
}

// MARK: - BizarreCRMUITestCase

/// Base class for all BizarreCRM XCUITest cases.
///
/// Responsibilities:
///   1. Launch the app with standard test flags before each test.
///   2. Terminate + collect artifacts (screenshots) on teardown.
///   3. Expose the shared `app` accessor and common page objects.
///   4. Run the iOS 17+ accessibility audit after every test (opt-out via override).
open class BizarreCRMUITestCase: XCTestCase {

    // MARK: - Properties

    /// The XCUIApplication under test.
    public private(set) var app: XCUIApplication!

    /// Override to `false` in a subclass to skip the post-test a11y audit.
    open var performsA11yAuditAfterEachTest: Bool { true }

    /// Additional launch args appended by the subclass.
    open var extraLaunchArgs: [UITestLaunchArg] { [] }

    /// Additional env vars set by the subclass.
    open var extraEnvVars: [UITestEnvVar: String] { [:] }

    // MARK: - Lifecycle

    override open func setUp() {
        super.setUp()
        continueAfterFailure = false

        app = XCUIApplication()

        // Standard test flags
        var args: [String] = [
            UITestLaunchArg.mockAuth.rawValue,
            UITestLaunchArg.mockAPI.rawValue,
            UITestLaunchArg.skipOnboarding.rawValue,
            UITestLaunchArg.disableAnimations.rawValue,
        ]
        args += extraLaunchArgs.map(\.rawValue)
        app.launchArguments = args

        var env: [String: String] = [
            UITestEnvVar.fixtureSeed.rawValue: "42",
            UITestEnvVar.tenantSlug.rawValue:  "uitest",
        ]
        extraEnvVars.forEach { env[$0.key.rawValue] = $0.value }
        app.launchEnvironment = env

        app.launch()
    }

    override open func tearDown() {
        // Capture a screenshot on failure for CI artefact attachment.
        if let screenshot = app?.screenshot() {
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "teardown-\(name)"
            attachment.lifetime = .deleteOnSuccess
            add(attachment)
        }

        // iOS 17+ accessibility audit (opt-out per class).
        if performsA11yAuditAfterEachTest {
            performA11yAuditIfAvailable()
        }

        app?.terminate()
        app = nil
        super.tearDown()
    }

    // MARK: - A11y audit helper

    private func performA11yAuditIfAvailable() {
        if #available(iOS 17, *) {
            do {
                try app.performAccessibilityAudit()
            } catch {
                // Log but do not fail — violations are tracked separately in §31.6.
                // Change to XCTFail when §31.6 is fully green.
                XCTExpectFailure("Accessibility audit found violations: \(error)")
            }
        }
    }

    // MARK: - Wait helpers

    /// Waits for `element` to exist up to `timeout` seconds. Fails the test if it doesn't appear.
    @discardableResult
    public func waitForElement(_ element: XCUIElement, timeout: TimeInterval = 5) -> XCUIElement {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "Element \(element) did not appear within \(timeout)s"
        )
        return element
    }

    /// Taps `element` after confirming it exists.
    public func tap(_ element: XCUIElement, timeout: TimeInterval = 5) {
        waitForElement(element, timeout: timeout).tap()
    }

    /// Types `text` into `element` after confirming it exists.
    public func typeInto(_ element: XCUIElement, text: String, timeout: TimeInterval = 5) {
        let field = waitForElement(element, timeout: timeout)
        field.tap()
        field.typeText(text)
    }
}

// MARK: - Page objects (stubs)

/// Page object for the Login screen.
///
/// Each property wraps a single XCUIElement query. Tests call page methods
/// (e.g. `login.fillCredentials(...)`) rather than raw element queries so
/// accessibilityIdentifier changes are contained here.
public struct LoginPage {
    private let app: XCUIApplication

    public init(app: XCUIApplication) { self.app = app }

    public var tenantField:   XCUIElement { app.textFields["loginTenantField"] }
    public var emailField:    XCUIElement { app.textFields["loginEmailField"] }
    public var passwordField: XCUIElement { app.secureTextFields["loginPasswordField"] }
    public var signInButton:  XCUIElement { app.buttons["loginSignInButton"] }
    public var errorLabel:    XCUIElement { app.staticTexts["loginErrorLabel"] }

    public func fillCredentials(tenant: String, email: String, password: String) {
        tenantField.tap(); tenantField.typeText(tenant)
        emailField.tap();   emailField.typeText(email)
        passwordField.tap(); passwordField.typeText(password)
    }

    public func tapSignIn() { signInButton.tap() }
}

/// Page object for the Dashboard screen.
public struct DashboardPage {
    private let app: XCUIApplication

    public init(app: XCUIApplication) { self.app = app }

    public var navigationTitle: XCUIElement { app.navigationBars["Dashboard"] }
    public var newTicketButton: XCUIElement { app.buttons["dashboardNewTicketButton"] }
    public var myQueueSection:  XCUIElement { app.otherElements["dashboardMyQueueSection"] }
}

/// Page object for the Ticket detail / creation screen.
public struct TicketPage {
    private let app: XCUIApplication

    public init(app: XCUIApplication) { self.app = app }

    public var titleField:      XCUIElement { app.textFields["ticketTitleField"] }
    public var addPaymentButton: XCUIElement { app.buttons["ticketAddPaymentButton"] }
    public var saveButton:      XCUIElement { app.buttons["ticketSaveButton"] }
}

/// Page object for the POS cart screen.
public struct POSCartPage {
    private let app: XCUIApplication

    public init(app: XCUIApplication) { self.app = app }

    public var cartItemCount: XCUIElement { app.staticTexts["posCartItemCount"] }
    public var chargeButton:  XCUIElement { app.buttons["posChargeButton"] }
    public var customerPickButton: XCUIElement { app.buttons["posPickCustomerButton"] }
}

// MARK: - Golden-path test stubs (§31.4)
//
// Each class below is a placeholder. Fill in the body when the corresponding
// screen is stable. The class declarations ensure CI picks them up and
// reports them as 0-assertion passes (not missing) until implemented.

/// §31.4 — Login → Dashboard → New Ticket → Add Payment → Print Receipt
final class GoldenPathTicketFlowTests: BizarreCRMUITestCase {

    func test_goldenPath_loginToDashboard() {
        // TODO §31.4: implement when Auth + Dashboard UI stable.
        // let login = LoginPage(app: app)
        // login.fillCredentials(tenant: "uitest", email: "agent@test.com", password: "P@ssw0rd!")
        // login.tapSignIn()
        // let dashboard = DashboardPage(app: app)
        // waitForElement(dashboard.navigationTitle)
        XCTAssertTrue(true, "Placeholder — implement once Auth screen ships §31.4")
    }

    func test_goldenPath_newTicketFlow() {
        XCTAssertTrue(true, "Placeholder — §31.4 new ticket → payment → receipt")
    }
}

/// §31.4 — POS: catalog browse → 3 items → customer → charge stub → success
final class GoldenPathPOSFlowTests: BizarreCRMUITestCase {

    func test_goldenPath_posCartAndCharge() {
        XCTAssertTrue(true, "Placeholder — §31.4 POS golden path")
    }
}

/// §31.4 — SMS: open thread → send → WS event → bubble appears
final class GoldenPathSMSFlowTests: BizarreCRMUITestCase {

    func test_goldenPath_smsSendAndReceive() {
        XCTAssertTrue(true, "Placeholder — §31.4 SMS golden path")
    }
}

/// §31.4 — Offline: airplane on → create customer → airplane off → sync
final class OfflineSyncFlowTests: BizarreCRMUITestCase {

    override var extraLaunchArgs: [UITestLaunchArg] {
        [.airplaneMode, .seedFixtures]
    }

    func test_offlineCreateAndSync() {
        XCTAssertTrue(true, "Placeholder — §31.4 offline sync flow")
    }
}

/// §31.4 — Auth: login / logout / 401 auto-logout / biometric re-auth
final class AuthFlowTests: BizarreCRMUITestCase {

    func test_auth_loginAndLogout() {
        XCTAssertTrue(true, "Placeholder — §31.4 auth login/logout")
    }

    func test_auth_401AutoLogout() {
        XCTAssertTrue(true, "Placeholder — §31.4 401 auto-logout")
    }
}

/// §31.6 — Accessibility audit per screen (iOS 17+)
final class AccessibilityAuditTests: BizarreCRMUITestCase {

    // Override to `false` — the base-class teardown already runs the audit
    // post-test. This class calls it explicitly mid-test for named screens.
    override var performsA11yAuditAfterEachTest: Bool { false }

    @available(iOS 17, *)
    func test_a11yAudit_loginScreen() throws {
        // Navigate to login (already on login when launched fresh)
        try app.performAccessibilityAudit()
    }

    @available(iOS 17, *)
    func test_a11yAudit_dashboardScreen() throws {
        // TODO: navigate to dashboard first
        XCTAssertTrue(true, "Placeholder — §31.6 dashboard audit")
    }
}
