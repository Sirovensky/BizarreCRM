import XCTest
@testable import Auth

/// §2.6 — biometric opt-in persistence. UserDefaults-backed so we can
/// assert the raw key survives encode/decode round trips.
@MainActor
final class BiometricPreferenceTests: XCTestCase {
    override func setUp() async throws {
        BiometricPreference.shared.disable()
    }

    override func tearDown() async throws {
        BiometricPreference.shared.disable()
    }

    func test_default_isDisabled() {
        XCTAssertFalse(BiometricPreference.shared.isEnabled)
    }

    func test_enable_persistsAcrossReads() {
        BiometricPreference.shared.enable()
        XCTAssertTrue(BiometricPreference.shared.isEnabled)
        // Re-read via raw UserDefaults to confirm we didn't stash it in an
        // in-memory cache by accident.
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "auth.biometric_enabled"))
    }

    func test_disable_clearsPreference() {
        BiometricPreference.shared.enable()
        BiometricPreference.shared.disable()
        XCTAssertFalse(BiometricPreference.shared.isEnabled)
    }

    func test_biometricKind_labels() {
        // Kind labels are user-visible; lock them so a cosmetic rename
        // can't silently break the accessible label copy.
        XCTAssertEqual(BiometricGate.Kind.none.label, "")
        XCTAssertEqual(BiometricGate.Kind.touchID.label, "Touch ID")
        XCTAssertEqual(BiometricGate.Kind.faceID.label, "Face ID")
        XCTAssertEqual(BiometricGate.Kind.opticID.label, "Optic ID")
    }

    func test_biometricKind_sfSymbols() {
        // SFSymbols — also user-visible; pinning here flags accidental
        // changes to nonexistent glyph names.
        XCTAssertEqual(BiometricGate.Kind.none.sfSymbol, "lock.fill")
        XCTAssertEqual(BiometricGate.Kind.touchID.sfSymbol, "touchid")
        XCTAssertEqual(BiometricGate.Kind.faceID.sfSymbol, "faceid")
        XCTAssertEqual(BiometricGate.Kind.opticID.sfSymbol, "opticid")
    }
}
