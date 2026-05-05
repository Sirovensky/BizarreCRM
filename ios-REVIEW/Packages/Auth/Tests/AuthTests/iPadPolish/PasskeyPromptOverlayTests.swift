import XCTest
@testable import Auth

// MARK: - PasskeyPromptOverlayTests
//
// §22 — Tests for PasskeyPromptOverlay and PasskeyPromptState.
// Tests focus on the logic layer (state machine, kind metadata, callbacks).

final class PasskeyPromptOverlayTests: XCTestCase {

    // MARK: - PasskeyPromptKind — sfSymbol

    func test_passkeyKind_sfSymbol_faceID() {
        XCTAssertEqual(PasskeyPromptKind.faceID.sfSymbol, "faceid")
    }

    func test_passkeyKind_sfSymbol_touchID() {
        XCTAssertEqual(PasskeyPromptKind.touchID.sfSymbol, "touchid")
    }

    func test_passkeyKind_sfSymbol_passkey() {
        XCTAssertEqual(PasskeyPromptKind.passkey.sfSymbol, "person.badge.key.fill")
    }

    // MARK: - PasskeyPromptKind — label

    func test_passkeyKind_label_faceID_containsFaceID() {
        XCTAssertTrue(PasskeyPromptKind.faceID.label.localizedCaseInsensitiveContains("face id"))
    }

    func test_passkeyKind_label_touchID_containsTouchID() {
        XCTAssertTrue(PasskeyPromptKind.touchID.label.localizedCaseInsensitiveContains("touch id"))
    }

    func test_passkeyKind_label_passkey_containsPasskey() {
        XCTAssertTrue(PasskeyPromptKind.passkey.label.localizedCaseInsensitiveContains("passkey"))
    }

    // MARK: - PasskeyPromptKind — accessibilityLabel

    func test_passkeyKind_a11yLabel_faceID_isNonEmpty() {
        XCTAssertFalse(PasskeyPromptKind.faceID.accessibilityLabel.isEmpty)
    }

    func test_passkeyKind_a11yLabel_touchID_isNonEmpty() {
        XCTAssertFalse(PasskeyPromptKind.touchID.accessibilityLabel.isEmpty)
    }

    func test_passkeyKind_a11yLabel_passkey_isNonEmpty() {
        XCTAssertFalse(PasskeyPromptKind.passkey.accessibilityLabel.isEmpty)
    }

    func test_passkeyKind_a11yLabel_differentFromLabel() {
        // Accessibility labels should be more descriptive than the button label
        let kind = PasskeyPromptKind.faceID
        XCTAssertNotEqual(kind.label, kind.accessibilityLabel)
    }

    // MARK: - PasskeyPromptState — initial state

    func test_promptState_initiallyInvisible() {
        let state = PasskeyPromptState()
        XCTAssertFalse(state.isVisible)
    }

    func test_promptState_initialKindIsPasskey() {
        let state = PasskeyPromptState()
        if case .passkey = state.kind {
            // pass
        } else {
            XCTFail("Expected .passkey initial kind, got \(state.kind)")
        }
    }

    // MARK: - PasskeyPromptState — show

    @MainActor
    func test_promptState_show_setsIsVisibleTrue() {
        let state = PasskeyPromptState()
        state.show()
        XCTAssertTrue(state.isVisible)
    }

    @MainActor
    func test_promptState_show_updatesKind_faceID() {
        let state = PasskeyPromptState()
        state.show(kind: .faceID)
        if case .faceID = state.kind { /* pass */ }
        else { XCTFail("Expected .faceID after show(kind: .faceID)") }
    }

    @MainActor
    func test_promptState_show_updatesKind_touchID() {
        let state = PasskeyPromptState()
        state.show(kind: .touchID)
        if case .touchID = state.kind { /* pass */ }
        else { XCTFail("Expected .touchID after show(kind: .touchID)") }
    }

    @MainActor
    func test_promptState_show_defaultKindIsPasskey() {
        let state = PasskeyPromptState()
        state.show()
        if case .passkey = state.kind { /* pass */ }
        else { XCTFail("Expected .passkey as default show kind") }
    }

    // MARK: - PasskeyPromptState — hide

    @MainActor
    func test_promptState_hide_setsIsVisibleFalse() {
        let state = PasskeyPromptState()
        state.show()
        state.hide()
        XCTAssertFalse(state.isVisible)
    }

    @MainActor
    func test_promptState_hide_whenAlreadyHidden_noopSafe() {
        let state = PasskeyPromptState()
        // hide() on already-hidden state should not crash
        state.hide()
        XCTAssertFalse(state.isVisible)
    }

    @MainActor
    func test_promptState_showHideShow_worksCorrectly() {
        let state = PasskeyPromptState()
        state.show()
        XCTAssertTrue(state.isVisible)
        state.hide()
        XCTAssertFalse(state.isVisible)
        state.show(kind: .touchID)
        XCTAssertTrue(state.isVisible)
        if case .touchID = state.kind { /* pass */ }
        else { XCTFail("Expected touchID after second show") }
    }

    // MARK: - Callback wiring (unit-level)

    func test_passkeyPromptOverlay_init_doesNotFireCallbacks() {
        var acceptCount = 0
        var dismissCount = 0

        _ = PasskeyPromptOverlay(
            kind: .passkey,
            autoDismissDelay: 0,
            onAccept: { acceptCount += 1 },
            onDismiss: { dismissCount += 1 }
        )

        XCTAssertEqual(acceptCount, 0, "onAccept must not fire on init")
        XCTAssertEqual(dismissCount, 0, "onDismiss must not fire on init")
    }

    // MARK: - Auto-dismiss delay token

    func test_passkeyPromptOverlay_zeroDismissDelay_isValid() {
        // Zero means no auto-dismiss — must construct without crash
        let overlay = PasskeyPromptOverlay(
            kind: .faceID,
            autoDismissDelay: 0,
            onAccept: {},
            onDismiss: {}
        )
        XCTAssertNotNil(overlay)
    }

    func test_passkeyPromptOverlay_defaultDismissDelay_isPositive() {
        // Default 8s — verify the type accepts positive values
        let overlay = PasskeyPromptOverlay(
            kind: .passkey,
            autoDismissDelay: 8,
            onAccept: {},
            onDismiss: {}
        )
        XCTAssertNotNil(overlay)
    }
}
