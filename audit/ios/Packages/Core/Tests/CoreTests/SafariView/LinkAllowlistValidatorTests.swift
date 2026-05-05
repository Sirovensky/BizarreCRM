import XCTest
@testable import Core

// MARK: - LinkAllowlistValidatorTests

/// Tests ``LinkAllowlistValidator``.
///
/// Coverage targets:
/// - HTTPS-only enforcement.
/// - Tenant host match (exact).
/// - Canonical app host always allowed.
/// - Apple privacy host always allowed.
/// - Extra allowed hosts respected.
/// - Unknown hosts are blocked.
/// - Non-HTTPS (http, custom schemes) are blocked.
/// - Missing host is blocked.
final class LinkAllowlistValidatorTests: XCTestCase {

    // MARK: - Helpers

    private func makeValidator(
        tenantHost: String = "app.bizarrecrm.com",
        extra: Set<String> = []
    ) -> LinkAllowlistValidator {
        LinkAllowlistValidator(tenantHost: tenantHost, extraAllowedHosts: extra)
    }

    private func url(_ s: String) -> URL {
        URL(string: s)!
    }

    // MARK: - Canonical app host

    func test_canonicalAppHost_isAllowed() {
        let v = makeValidator()
        let result = v.validate(url("https://app.bizarrecrm.com/track/TKT-1"))
        XCTAssertTrue(result.isAllowed)
    }

    // MARK: - Apple privacy host

    func test_applePrivacyHost_isAllowed() {
        let v = makeValidator()
        let result = v.validate(url("https://www.apple.com/privacy"))
        XCTAssertTrue(result.isAllowed)
    }

    // MARK: - Tenant host

    func test_tenantHost_exactMatch_isAllowed() {
        let v = makeValidator(tenantHost: "app.acme.com")
        let result = v.validate(url("https://app.acme.com/pay/LNK-9"))
        XCTAssertTrue(result.isAllowed)
    }

    func test_tenantHost_caseInsensitive_isAllowed() {
        let v = makeValidator(tenantHost: "APP.ACME.COM")
        let result = v.validate(url("https://app.acme.com/dashboard"))
        XCTAssertTrue(result.isAllowed)
    }

    func test_tenantHost_subdomain_isBlocked() {
        let v = makeValidator(tenantHost: "acme.com")
        // sub.acme.com is NOT acme.com — exact match required
        let result = v.validate(url("https://sub.acme.com/page"))
        XCTAssertFalse(result.isAllowed)
        if case .blocked(let reason) = result {
            XCTAssertTrue(reason.contains("sub.acme.com"))
        } else {
            XCTFail("Expected blocked result")
        }
    }

    // MARK: - Extra hosts

    func test_extraAllowedHost_isAllowed() {
        let v = makeValidator(extra: ["docs.bizarrecrm.com"])
        let result = v.validate(url("https://docs.bizarrecrm.com/guide"))
        XCTAssertTrue(result.isAllowed)
    }

    func test_extraAllowedHost_caseInsensitive_isAllowed() {
        let v = makeValidator(extra: ["DOCS.BIZARRECRM.COM"])
        let result = v.validate(url("https://docs.bizarrecrm.com/guide"))
        XCTAssertTrue(result.isAllowed)
    }

    // MARK: - Unknown hosts

    func test_unknownHost_isBlocked() {
        let v = makeValidator()
        let result = v.validate(url("https://evil.example.com/phishing"))
        XCTAssertFalse(result.isAllowed)
    }

    func test_unknownHost_blockedReason_containsHost() {
        let v = makeValidator()
        if case .blocked(let reason) = v.validate(url("https://attacker.io/page")) {
            XCTAssertTrue(reason.contains("attacker.io"))
        } else {
            XCTFail("Expected blocked result")
        }
    }

    // MARK: - HTTP blocked

    func test_httpScheme_isBlocked() {
        let v = makeValidator()
        let result = v.validate(url("http://app.bizarrecrm.com/track/TKT-1"))
        XCTAssertFalse(result.isAllowed)
        if case .blocked(let reason) = result {
            XCTAssertTrue(reason.lowercased().contains("https"))
        } else {
            XCTFail("Expected blocked result")
        }
    }

    // MARK: - Custom scheme blocked

    func test_customScheme_isBlocked() {
        let v = makeValidator()
        let result = v.validate(url("bizarrecrm://app.bizarrecrm.com/track/TKT-1"))
        XCTAssertFalse(result.isAllowed)
    }

    // MARK: - Result helpers

    func test_allowedResult_isAllowedTrue() {
        XCTAssertTrue(LinkAllowlistValidator.Result.allowed.isAllowed)
    }

    func test_blockedResult_isAllowedFalse() {
        XCTAssertFalse(LinkAllowlistValidator.Result.blocked(reason: "test").isAllowed)
    }

    // MARK: - Static constants

    func test_applePrivacyHost_constant() {
        XCTAssertEqual(LinkAllowlistValidator.applePrivacyHost, "www.apple.com")
    }

    func test_canonicalAppHost_constant_matchesDeepLinkParser() {
        XCTAssertEqual(
            LinkAllowlistValidator.canonicalAppHost,
            DeepLinkURLParser.universalLinkHost
        )
    }
}
