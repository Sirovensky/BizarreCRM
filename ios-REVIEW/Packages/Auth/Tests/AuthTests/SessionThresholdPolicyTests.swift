import XCTest
@testable import Auth

final class SessionThresholdPolicyTests: XCTestCase {

    func test_defaultThresholds_areAtGlobalMaxima() {
        let policy = SessionThresholdPolicy()
        XCTAssertEqual(policy.biometricTimeout,  15 * 60,             accuracy: 1)
        XCTAssertEqual(policy.passwordTimeout,   4 * 60 * 60,         accuracy: 1)
        XCTAssertEqual(policy.fullReauthTimeout, 30 * 24 * 60 * 60,   accuracy: 1)
    }

    func test_requiredLevel_belowBiometricThreshold_isNone() {
        let policy = SessionThresholdPolicy()
        XCTAssertEqual(policy.requiredLevel(idleSeconds: 0), .none)
        XCTAssertEqual(policy.requiredLevel(idleSeconds: 14 * 60), .none)
    }

    func test_requiredLevel_atBiometricThreshold_isBiometric() {
        let policy = SessionThresholdPolicy()
        XCTAssertEqual(policy.requiredLevel(idleSeconds: 15 * 60), .biometric)
        XCTAssertEqual(policy.requiredLevel(idleSeconds: 20 * 60), .biometric)
    }

    func test_requiredLevel_atPasswordThreshold_isPassword() {
        let policy = SessionThresholdPolicy()
        XCTAssertEqual(policy.requiredLevel(idleSeconds: 4 * 60 * 60), .password)
    }

    func test_requiredLevel_atFullReauthThreshold_isFullWithEmail() {
        let policy = SessionThresholdPolicy()
        XCTAssertEqual(policy.requiredLevel(idleSeconds: 30 * 24 * 60 * 60), .fullWithEmail)
    }

    func test_clamping_tenantCannotExceedGlobalMaxima() {
        // Tenant tries to set biometric = 1h, password = 48h, full = 365d
        let policy = SessionThresholdPolicy(
            biometricTimeout:  1 * 60 * 60,
            passwordTimeout:   48 * 60 * 60,
            fullReauthTimeout: 365 * 24 * 60 * 60
        )
        XCTAssertLessThanOrEqual(policy.biometricTimeout,  SessionThresholdPolicy.maxBiometricTimeout)
        XCTAssertLessThanOrEqual(policy.passwordTimeout,   SessionThresholdPolicy.maxPasswordTimeout)
        XCTAssertLessThanOrEqual(policy.fullReauthTimeout, SessionThresholdPolicy.maxFullReauthTimeout)
    }

    func test_tenantPolicy_resolved_shortensThresholds() {
        let tenantPolicy = TenantSessionPolicy(
            biometricTimeoutSeconds: 5 * 60,    // 5 min
            passwordTimeoutSeconds:  30 * 60,   // 30 min
            fullReauthTimeoutSeconds: 7 * 24 * 60 * 60  // 7 days
        )
        let resolved = tenantPolicy.resolved()
        XCTAssertEqual(resolved.biometricTimeout,  5 * 60,           accuracy: 1)
        XCTAssertEqual(resolved.passwordTimeout,   30 * 60,          accuracy: 1)
        XCTAssertEqual(resolved.fullReauthTimeout, 7 * 24 * 60 * 60, accuracy: 1)
    }

    func test_reauthLevel_ordering() {
        XCTAssertLessThan(ReauthLevel.none, ReauthLevel.biometric)
        XCTAssertLessThan(ReauthLevel.biometric, ReauthLevel.password)
        XCTAssertLessThan(ReauthLevel.password, ReauthLevel.fullWithEmail)
    }
}
