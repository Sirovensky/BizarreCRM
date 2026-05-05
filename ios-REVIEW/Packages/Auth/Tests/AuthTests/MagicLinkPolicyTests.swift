import XCTest
@testable import Auth

final class MagicLinkPolicyTests: XCTestCase {

    func test_universalLink_isFromPinnedDomain() {
        let policy = MagicLinkPolicy()
        let url = URL(string: "https://app.bizarrecrm.com/auth/magic?token=abc")!
        XCTAssertTrue(policy.isFromPinnedDomain(url))
    }

    func test_customScheme_isFromPinnedDomain() {
        let policy = MagicLinkPolicy()
        let url = URL(string: "bizarrecrm://auth/magic?token=abc")!
        XCTAssertTrue(policy.isFromPinnedDomain(url))
    }

    func test_otherDomain_isNotPinned() {
        let policy = MagicLinkPolicy()
        let url = URL(string: "https://evil.com/auth/magic?token=abc")!
        XCTAssertFalse(policy.isFromPinnedDomain(url))
    }

    func test_validMagicLink_enabledTenant() {
        let policy = MagicLinkPolicy(magicLinksEnabled: true)
        let url = URL(string: "https://app.bizarrecrm.com/auth/magic?token=abc")!
        XCTAssertTrue(policy.isValidMagicLink(url))
    }

    func test_validMagicLink_disabledTenant() {
        let policy = MagicLinkPolicy(magicLinksEnabled: false)
        let url = URL(string: "https://app.bizarrecrm.com/auth/magic?token=abc")!
        XCTAssertFalse(policy.isValidMagicLink(url), "Tenant disabled magic links")
    }

    func test_withinLifetime_recentToken() {
        let policy = MagicLinkPolicy()
        let issuedAt = Date(timeIntervalSinceNow: -60) // 1 min ago
        XCTAssertTrue(policy.isWithinLifetime(issuedAt: issuedAt))
    }

    func test_outsideLifetime_expiredToken() {
        let policy = MagicLinkPolicy()
        let issuedAt = Date(timeIntervalSinceNow: -(16 * 60)) // 16 min ago
        XCTAssertFalse(policy.isWithinLifetime(issuedAt: issuedAt))
    }

    func test_futureToken_isInvalid() {
        let policy = MagicLinkPolicy()
        let issuedAt = Date(timeIntervalSinceNow: 60) // 1 min in the future
        XCTAssertFalse(policy.isWithinLifetime(issuedAt: issuedAt))
    }

    func test_pinnedDomain_constant() {
        XCTAssertEqual(MagicLinkPolicy.pinnedDomain, "app.bizarrecrm.com")
    }

    func test_maxLifetime_is15Minutes() {
        XCTAssertEqual(MagicLinkPolicy.maxTokenLifetimeSeconds, 15 * 60, accuracy: 1)
    }
}
