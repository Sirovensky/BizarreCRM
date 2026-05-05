import XCTest
import LocalAuthentication
import UIKit
@testable import Auth
@testable import Core
@testable import Tickets

// §28 b2 — Extended edge-case tests for biometric prompt strings,
// screenshot audit counter notification wiring, sensitive-field sentinel,
// TicketPIIRedactor category invariants, and TicketPasteBlind expiry policy.
//
// These tests supplement the batch-2 suite (BiometricPromptStringsTests) and
// cover six specific edge cases called out in the §28 action-plan review.

// MARK: - BiometricPromptStrings edge cases

final class BiometricPromptStringsExtTests: XCTestCase {

    // MARK: - 1. signIn(.faceID) contains "Face ID"

    /// §28.10 — `.signIn(kind: .faceID)` must embed the string "Face ID" so the
    /// OS prompt can display the correct modality label to the user.
    func test_signIn_faceID_reasonContainsFaceID() {
        let reason = BiometricPromptStrings.signIn(kind: .faceID).reason
        XCTAssertTrue(
            reason.contains("Face ID"),
            "signIn(.faceID).reason must contain 'Face ID'; got: \(reason)"
        )
    }

    // MARK: - 2. signIn(.touchID) contains "Touch ID"

    /// §28.10 — `.signIn(kind: .touchID)` must embed "Touch ID" so the string is
    /// appropriate on devices that do not have Face ID.
    func test_signIn_touchID_reasonContainsTouchID() {
        let reason = BiometricPromptStrings.signIn(kind: .touchID).reason
        XCTAssertTrue(
            reason.contains("Touch ID"),
            "signIn(.touchID).reason must contain 'Touch ID'; got: \(reason)"
        )
    }

    // MARK: - 3. signIn(.faceID) does NOT contain "Touch ID" and vice-versa

    /// Guard against a copy-paste bug where the wrong modality label is embedded.
    func test_signIn_faceID_doesNotContainTouchID() {
        let reason = BiometricPromptStrings.signIn(kind: .faceID).reason
        XCTAssertFalse(
            reason.contains("Touch ID"),
            "signIn(.faceID).reason must not contain 'Touch ID'; got: \(reason)"
        )
    }

    func test_signIn_touchID_doesNotContainFaceID() {
        let reason = BiometricPromptStrings.signIn(kind: .touchID).reason
        XCTAssertFalse(
            reason.contains("Face ID"),
            "signIn(.touchID).reason must not contain 'Face ID'; got: \(reason)"
        )
    }
}

// MARK: - ScreenshotAuditCounter notification wiring

/// §28.8 — Verify that `ScreenshotAuditCounter.attach()` wires up to
/// `UIApplication.userDidTakeScreenshotNotification` so the `onScreenshot`
/// closure fires when the notification posts.
///
/// The real `ScreenshotAuditCounter` registers an `NSNotificationCenter`
/// observer inside `attach()`.  We post the notification manually (no actual
/// screenshot needed) and assert the closure is invoked.
@MainActor
final class ScreenshotAuditCounterNotificationTests: XCTestCase {

    func test_attach_invokesOnScreenshot_whenNotificationPosts() {
        let counter = ScreenshotAuditCounter()
        var receivedEntry: ScreenshotAuditEntry?
        let expectation = expectation(description: "onScreenshot closure called")

        counter.attach(screenIdentifier: "sensitive-screen", userID: "u99") { entry in
            receivedEntry = entry
            expectation.fulfill()
        }

        // Post the real notification that iOS fires when a screenshot is taken.
        NotificationCenter.default.post(
            name: UIApplication.userDidTakeScreenshotNotification,
            object: nil
        )

        // The observer dispatches to @MainActor via a Task; give it a brief
        // chance to execute on the same run-loop turn.
        waitForExpectations(timeout: 1.0)

        XCTAssertEqual(receivedEntry?.screenIdentifier, "sensitive-screen")
        XCTAssertEqual(receivedEntry?.userID, "u99")
        XCTAssertEqual(counter.count, 1)

        counter.detach()
    }

    func test_attach_countIncrements_whenNotificationPosts() {
        let counter = ScreenshotAuditCounter()
        let exp1 = expectation(description: "first screenshot")
        let exp2 = expectation(description: "second screenshot")
        var callCount = 0

        counter.attach(screenIdentifier: "receipts", userID: nil) { _ in
            callCount += 1
            if callCount == 1 { exp1.fulfill() }
            if callCount == 2 { exp2.fulfill() }
        }

        NotificationCenter.default.post(name: UIApplication.userDidTakeScreenshotNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.userDidTakeScreenshotNotification, object: nil)

        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(counter.count, 2)

        counter.detach()
    }
}

// MARK: - @SensitiveField CustomStringConvertible sentinel

/// §28.7 — Direct string interpolation of a `@SensitiveField` (without `$`)
/// must yield a sentinel containing "SENSITIVE" so log-scraper rules can catch
/// accidental raw PII leakage in CI output.
final class SensitiveFieldCustomStringConvertibleTests: XCTestCase {

    func test_description_containsSENTINEL() {
        // Construct the wrapper directly (as a value, not inside a struct).
        // This mirrors what happens when a dev writes `"\(someWrapper)"` by mistake.
        let field = SensitiveField<String>(wrappedValue: "alice@example.com", .email)
        let interpolated = "\(field)"
        XCTAssertTrue(
            interpolated.contains("SENSITIVE"),
            "Direct interpolation of SensitiveField must contain 'SENSITIVE'; got: \(interpolated)"
        )
    }

    func test_description_doesNotLeakRawValue() {
        let field = SensitiveField<String>(wrappedValue: "alice@example.com", .email)
        let interpolated = "\(field)"
        XCTAssertFalse(
            interpolated.contains("alice@example.com"),
            "SensitiveField description must not expose raw PII; got: \(interpolated)"
        )
    }

    func test_debugDescription_containsSENTINEL() {
        let field = SensitiveField<String>(wrappedValue: "secret", .email)
        XCTAssertTrue(
            field.debugDescription.contains("SENSITIVE"),
            "debugDescription must contain 'SENSITIVE'; got: \(field.debugDescription)"
        )
    }
}

// MARK: - TicketPIIRedactor category invariants

/// §28.7/§28.8 — `TicketPIIRedactor.ticketTextCategories` must exclude
/// `.paymentCard` because tickets never store PANs.  Adding payment card
/// patterns to ticket-text redaction would produce false positives in
/// number-heavy device-serial fields.
final class TicketPIIRedactorCategoryTests: XCTestCase {

    func test_ticketTextCategories_excludesPaymentCard() {
        XCTAssertFalse(
            TicketPIIRedactor.ticketTextCategories.contains(.paymentCard),
            "ticketTextCategories must not include .paymentCard; tickets never store PANs"
        )
    }

    func test_ticketTextCategories_includesEmail() {
        XCTAssertTrue(
            TicketPIIRedactor.ticketTextCategories.contains(.email),
            "ticketTextCategories must include .email"
        )
    }

    func test_ticketTextCategories_includesPhone() {
        XCTAssertTrue(
            TicketPIIRedactor.ticketTextCategories.contains(.phone),
            "ticketTextCategories must include .phone"
        )
    }

    func test_ticketTextCategories_includesDeviceID() {
        XCTAssertTrue(
            TicketPIIRedactor.ticketTextCategories.contains(.deviceID),
            "ticketTextCategories must include .deviceID"
        )
    }
}

// MARK: - TicketPasteBlind sensitive-copy expiry

/// §28.9 — All sensitive pasteboard writes (email, phone, device serial) must
/// use a 120-second TTL.  `sensitiveExpirySeconds` is the canonical constant;
/// the individual `copyEmail`/`copyPhone`/`copyDeviceSerial` methods must all
/// reference it so the policy is enforced uniformly.
final class TicketPasteBlindExpiryTests: XCTestCase {

    func test_sensitiveExpirySeconds_is120() {
        XCTAssertEqual(
            TicketPasteBlind.sensitiveExpirySeconds,
            120,
            "Sensitive clipboard items must expire after exactly 120 seconds"
        )
    }

    func test_copyEmail_invokesOnCopy_withExpiryHint() {
        var auditString: String?
        TicketPasteBlind.copyEmail("alice@example.com") { audit in
            auditString = audit
        }
        let audit = try! XCTUnwrap(auditString)
        XCTAssertTrue(
            audit.contains("120"),
            "copyEmail audit string must mention the 120s expiry; got: \(audit)"
        )
        // Raw PII must NOT appear in the audit string.
        XCTAssertFalse(
            audit.contains("alice@example.com"),
            "copyEmail audit must not contain raw email address; got: \(audit)"
        )
    }

    func test_copyPhone_invokesOnCopy_withExpiryHint() {
        var auditString: String?
        TicketPasteBlind.copyPhone("555-0100") { audit in
            auditString = audit
        }
        let audit = try! XCTUnwrap(auditString)
        XCTAssertTrue(
            audit.contains("120"),
            "copyPhone audit string must mention the 120s expiry; got: \(audit)"
        )
        XCTAssertFalse(
            audit.contains("555-0100"),
            "copyPhone audit must not contain raw phone number; got: \(audit)"
        )
    }

    func test_copyDeviceSerial_invokesOnCopy_withExpiryHint() {
        var auditString: String?
        TicketPasteBlind.copyDeviceSerial("SN-ABC123") { audit in
            auditString = audit
        }
        let audit = try! XCTUnwrap(auditString)
        XCTAssertTrue(
            audit.contains("120"),
            "copyDeviceSerial audit string must mention the 120s expiry; got: \(audit)"
        )
        XCTAssertFalse(
            audit.contains("SN-ABC123"),
            "copyDeviceSerial audit must not contain raw serial; got: \(audit)"
        )
    }

    func test_nilOnCopy_doesNotCrash() {
        // Passing nil for onCopy must be safe — no crash, no assertion.
        TicketPasteBlind.copyEmail("b@example.com", onCopy: nil)
        TicketPasteBlind.copyPhone("555-9999", onCopy: nil)
        TicketPasteBlind.copyDeviceSerial("SN-XYZ", onCopy: nil)
    }
}
