import XCTest
@testable import Core

// MARK: - ExternalLinkPresenterTests

/// Tests ``ExternalLinkPresenter`` URL classification and presentation routing.
///
/// Coverage targets:
/// - Public tracking / pay / estimate URLs route to `.safari`.
/// - Generic allowed URLs route to `.safari`.
/// - Generic blocked URLs route to `.blocked`.
/// - Non-HTTPS (tel:, mailto:, bizarrecrm:) route to `.system`.
/// - `classify` helper returns the right `LinkKind` for each URL shape.
final class ExternalLinkPresenterTests: XCTestCase {

    // MARK: - Setup

    private var presenter: ExternalLinkPresenter!

    override func setUp() {
        super.setUp()
        let validator = LinkAllowlistValidator(tenantHost: "app.bizarrecrm.com")
        presenter = ExternalLinkPresenter(allowlistValidator: validator)
    }

    private func url(_ s: String) -> URL { URL(string: s)! }

    // MARK: - Public tracking links → .safari

    func test_publicTrackingURL_routesToSafari() {
        let u = url("https://app.bizarrecrm.com/track/TKT-001")
        if case .safari(let resolved) = presenter.presentation(for: u) {
            XCTAssertEqual(resolved, u)
        } else {
            XCTFail("Expected .safari, got \(presenter.presentation(for: u))")
        }
    }

    func test_publicPaymentURL_routesToSafari() {
        let u = url("https://app.bizarrecrm.com/pay/LNK-555")
        if case .safari = presenter.presentation(for: u) {
            // pass
        } else {
            XCTFail("Expected .safari")
        }
    }

    func test_publicEstimateURL_routesToSafari() {
        let u = url("https://app.bizarrecrm.com/estimate/EST-9")
        if case .safari = presenter.presentation(for: u) {
            // pass
        } else {
            XCTFail("Expected .safari")
        }
    }

    // MARK: - Generic allowed URL → .safari

    func test_genericAllowedURL_routesToSafari() {
        let u = url("https://app.bizarrecrm.com/settings")
        if case .safari = presenter.presentation(for: u) {
            // pass
        } else {
            XCTFail("Expected .safari for allowlisted host")
        }
    }

    // MARK: - Generic blocked URL → .blocked

    func test_genericBlockedURL_routesToBlocked() {
        let u = url("https://evil.example.com/phishing")
        if case .blocked = presenter.presentation(for: u) {
            // pass
        } else {
            XCTFail("Expected .blocked for non-allowlisted host")
        }
    }

    func test_blockedURL_reasonIsNonEmpty() {
        let u = url("https://evil.example.com/phishing")
        if case .blocked(let reason) = presenter.presentation(for: u) {
            XCTAssertFalse(reason.isEmpty)
        } else {
            XCTFail("Expected .blocked")
        }
    }

    // MARK: - Non-HTTPS schemes → .system

    func test_telScheme_routesToSystem() {
        let u = url("tel:+15551234567")
        if case .system(let resolved) = presenter.presentation(for: u) {
            XCTAssertEqual(resolved, u)
        } else {
            XCTFail("Expected .system for tel: scheme")
        }
    }

    func test_mailtoScheme_routesToSystem() {
        let u = url("mailto:support@bizarrecrm.com")
        if case .system = presenter.presentation(for: u) {
            // pass
        } else {
            XCTFail("Expected .system for mailto: scheme")
        }
    }

    func test_customScheme_routesToSystem() {
        let u = url("bizarrecrm://acme/dashboard")
        if case .system = presenter.presentation(for: u) {
            // pass
        } else {
            XCTFail("Expected .system for custom scheme")
        }
    }

    func test_httpScheme_isBlockedNotSystem() {
        // http:// is not non-HTTP, it falls into .generic which then hits the allowlist.
        // The allowlist only allows https, so this must be blocked.
        let u = url("http://app.bizarrecrm.com/dashboard")
        if case .blocked = presenter.presentation(for: u) {
            // pass — allowlist rejects http
        } else {
            XCTFail("Expected .blocked for http:// link (allowlist requires https)")
        }
    }

    // MARK: - classify helper

    func test_classify_trackPath_returnsPublicTracking() {
        let u = url("https://app.bizarrecrm.com/track/X")
        XCTAssertEqual(presenter.classify(u), .publicTracking)
    }

    func test_classify_payPath_returnsPublicPayment() {
        let u = url("https://app.bizarrecrm.com/pay/X")
        XCTAssertEqual(presenter.classify(u), .publicPayment)
    }

    func test_classify_estimatePath_returnsPublicEstimate() {
        let u = url("https://app.bizarrecrm.com/estimate/X")
        XCTAssertEqual(presenter.classify(u), .publicEstimate)
    }

    func test_classify_genericHTTPS_returnsGeneric() {
        let u = url("https://app.bizarrecrm.com/dashboard")
        XCTAssertEqual(presenter.classify(u), .generic)
    }

    func test_classify_telScheme_returnsNonHTTP() {
        let u = url("tel:+15559990000")
        XCTAssertEqual(presenter.classify(u), .nonHTTP)
    }

    func test_classify_customScheme_returnsNonHTTP() {
        let u = url("bizarrecrm://acme/dashboard")
        XCTAssertEqual(presenter.classify(u), .nonHTTP)
    }
}
