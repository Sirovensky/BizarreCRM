import XCTest
@testable import Voice
import Networking

/// §22 — Logic tests for `VoiceContextMenu` modifier behaviour.
///
/// `VoiceCallContextMenuModifier` wraps a SwiftUI `.contextMenu`. Since
/// SwiftUI context-menu presentation cannot be driven from a headless test
/// host, we verify:
///
///   1. The `CallQuickAction.cleanPhoneNumber` round-trip used by Callback.
///   2. The optional / conditional logic controlling which actions are present
///      (onAddToCustomer, onArchive nil vs non-nil).
///   3. That the display name falls back from `customerName` to `phoneNumber`
///      as expected by the menu label.
///
/// The closures themselves are fire-and-forget; action tests check invocation
/// counts via captured state.
final class VoiceContextMenuTests: XCTestCase {

    // MARK: - Helpers

    private func makeCallEntry(
        phoneNumber: String = "5551234567",
        customerName: String? = nil
    ) -> CallLogEntry {
        CallLogEntry(
            id: 1,
            direction: "inbound",
            phoneNumber: phoneNumber,
            customerName: customerName
        )
    }

    private func makeVoicemailEntry(
        phoneNumber: String = "5551234567",
        customerName: String? = nil
    ) -> VoicemailEntry {
        VoicemailEntry(
            id: 1,
            phoneNumber: phoneNumber,
            customerName: customerName
        )
    }

    // MARK: - Display name derivation

    func test_displayName_usesCustomerNameWhenPresent() {
        let entry = makeCallEntry(phoneNumber: "5551234567", customerName: "Alice")
        // The modifier is constructed by the view extension; verify the label
        // would use customerName over phoneNumber.
        let modifier = VoiceCallContextMenuModifier(
            phoneNumber: entry.phoneNumber,
            displayName: entry.customerName ?? entry.phoneNumber,
            onAddToCustomer: nil,
            onArchive: nil
        )
        XCTAssertEqual(modifier.displayName, "Alice")
    }

    func test_displayName_fallsBackToPhoneNumber() {
        let entry = makeCallEntry(phoneNumber: "5551234567", customerName: nil)
        let modifier = VoiceCallContextMenuModifier(
            phoneNumber: entry.phoneNumber,
            displayName: entry.customerName ?? entry.phoneNumber,
            onAddToCustomer: nil,
            onArchive: nil
        )
        XCTAssertEqual(modifier.displayName, "5551234567")
    }

    func test_displayName_voicemailUsesCustomerName() {
        let entry = makeVoicemailEntry(phoneNumber: "5550001111", customerName: "Bob")
        let modifier = VoiceCallContextMenuModifier(
            phoneNumber: entry.phoneNumber,
            displayName: entry.customerName ?? entry.phoneNumber,
            onAddToCustomer: nil,
            onArchive: nil
        )
        XCTAssertEqual(modifier.displayName, "Bob")
    }

    // MARK: - Phone number propagation

    func test_phoneNumber_isPassedThrough() {
        let entry = makeCallEntry(phoneNumber: "+14155550100")
        let modifier = VoiceCallContextMenuModifier(
            phoneNumber: entry.phoneNumber,
            displayName: entry.customerName ?? entry.phoneNumber,
            onAddToCustomer: nil,
            onArchive: nil
        )
        XCTAssertEqual(modifier.phoneNumber, "+14155550100")
    }

    // MARK: - Optional action presence

    func test_onAddToCustomer_nilMeansHidden() {
        let modifier = VoiceCallContextMenuModifier(
            phoneNumber: "5551234567",
            displayName: "Alice",
            onAddToCustomer: nil,
            onArchive: nil
        )
        XCTAssertNil(modifier.onAddToCustomer,
                     "Nil onAddToCustomer should hide the menu item")
    }

    func test_onArchive_nilMeansHidden() {
        let modifier = VoiceCallContextMenuModifier(
            phoneNumber: "5551234567",
            displayName: "Alice",
            onAddToCustomer: nil,
            onArchive: nil
        )
        XCTAssertNil(modifier.onArchive,
                     "Nil onArchive should hide the Archive item")
    }

    func test_onAddToCustomer_nonNilMeansVisible() {
        var called = false
        let modifier = VoiceCallContextMenuModifier(
            phoneNumber: "5551234567",
            displayName: "Alice",
            onAddToCustomer: { called = true },
            onArchive: nil
        )
        XCTAssertNotNil(modifier.onAddToCustomer)
        modifier.onAddToCustomer?()
        XCTAssertTrue(called)
    }

    func test_onArchive_nonNilMeansVisible_andIsInvocable() {
        var archiveCalled = false
        let modifier = VoiceCallContextMenuModifier(
            phoneNumber: "5551234567",
            displayName: "Alice",
            onAddToCustomer: nil,
            onArchive: { archiveCalled = true }
        )
        XCTAssertNotNil(modifier.onArchive)
        modifier.onArchive?()
        XCTAssertTrue(archiveCalled)
    }

    // MARK: - CallQuickAction.cleanPhoneNumber (used by Callback action)

    func test_callback_cleanPhoneNumber_stripsFormatting() {
        XCTAssertEqual(
            CallQuickAction.cleanPhoneNumber("(555) 123-4567"),
            "5551234567"
        )
    }

    func test_callback_cleanPhoneNumber_preservesLeadingPlus() {
        XCTAssertEqual(
            CallQuickAction.cleanPhoneNumber("+1-415-555-1212"),
            "+14155551212"
        )
    }

    func test_callback_cleanPhoneNumber_stripsUS11DigitPrefix() {
        XCTAssertEqual(
            CallQuickAction.cleanPhoneNumber("1 (800) 555-0100"),
            "8005550100"
        )
    }

    func test_callback_cleanPhoneNumber_emptyInputReturnsEmpty() {
        XCTAssertEqual(CallQuickAction.cleanPhoneNumber(""), "")
    }

    // MARK: - Multiple independent action invocations

    func test_bothOptionalActions_canBeInvokedIndependently() {
        var addCount = 0
        var archiveCount = 0
        let modifier = VoiceCallContextMenuModifier(
            phoneNumber: "5551234567",
            displayName: "Alice",
            onAddToCustomer: { addCount += 1 },
            onArchive: { archiveCount += 1 }
        )
        modifier.onAddToCustomer?()
        modifier.onAddToCustomer?()
        modifier.onArchive?()
        XCTAssertEqual(addCount, 2)
        XCTAssertEqual(archiveCount, 1)
    }
}
