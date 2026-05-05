import XCTest
import LocalAuthentication
@testable import Auth

// §28.10 — Unit tests for BiometricPromptStrings

final class BiometricPromptStringsTests: XCTestCase {

    // MARK: - signIn

    func test_signIn_faceID_containsFaceID() {
        let reason = BiometricPromptStrings.signIn(kind: .faceID).reason
        XCTAssertTrue(reason.contains("Face ID"), "Expected 'Face ID' in: \(reason)")
    }

    func test_signIn_touchID_containsTouchID() {
        let reason = BiometricPromptStrings.signIn(kind: .touchID).reason
        XCTAssertTrue(reason.contains("Touch ID"), "Expected 'Touch ID' in: \(reason)")
    }

    func test_signIn_noneKind_containsGenericBiometrics() {
        let reason = BiometricPromptStrings.signIn(kind: .none).reason
        XCTAssertTrue(reason.contains("biometrics"), "Expected 'biometrics' in: \(reason)")
    }

    func test_signIn_defaultKind_doesNotContainSpecificModality() {
        // Default kind is .none — should NOT say Face ID or Touch ID
        let reason = BiometricPromptStrings.signIn().reason
        XCTAssertFalse(reason.contains("Face ID"))
        XCTAssertFalse(reason.contains("Touch ID"))
    }

    // MARK: - sensitiveSettings

    func test_sensitiveSettings_faceID_mentionsSettings() {
        let reason = BiometricPromptStrings.sensitiveSettings(kind: .faceID).reason
        XCTAssertTrue(reason.lowercased().contains("settings"), reason)
    }

    // MARK: - voidTransaction

    func test_voidTransaction_containsVoid() {
        let reason = BiometricPromptStrings.voidTransaction(kind: .faceID).reason
        XCTAssertTrue(reason.lowercased().contains("void"), reason)
    }

    // MARK: - deleteCustomer

    func test_deleteCustomer_containsDelete() {
        let reason = BiometricPromptStrings.deleteCustomer(kind: .touchID).reason
        XCTAssertTrue(reason.lowercased().contains("delete"), reason)
    }

    // MARK: - exportAuditData

    func test_exportAuditData_containsExport() {
        let reason = BiometricPromptStrings.exportAuditData().reason
        XCTAssertTrue(reason.lowercased().contains("export"), reason)
    }

    // MARK: - revealBackupCodes

    func test_revealBackupCodes_containsBackup() {
        let reason = BiometricPromptStrings.revealBackupCodes(kind: .faceID).reason
        XCTAssertTrue(reason.lowercased().contains("backup"), reason)
    }

    // MARK: - managerOverride

    func test_managerOverride_containsManager() {
        let reason = BiometricPromptStrings.managerOverride(kind: .faceID).reason
        XCTAssertTrue(reason.lowercased().contains("manager"), reason)
    }

    // MARK: - Length guardrail (Apple recommends < 60 chars for usability)

    func test_allReasonStrings_areSensibleLength() {
        let cases: [BiometricPromptStrings] = [
            .signIn(kind: .faceID),
            .sensitiveSettings(kind: .faceID),
            .voidTransaction(kind: .faceID),
            .deleteCustomer(kind: .faceID),
            .exportAuditData(kind: .faceID),
            .revealBackupCodes(kind: .faceID),
            .managerOverride(kind: .faceID),
        ]
        for item in cases {
            XCTAssertLessThanOrEqual(
                item.reason.count, 100,
                "Reason string too long (\(item.reason.count) chars): \(item.reason)"
            )
            XCTAssertGreaterThan(item.reason.count, 10, "Reason string suspiciously short: \(item.reason)")
        }
    }
}
