import XCTest
@testable import Core

// §64 — Tests for ConfirmationCopy catalog completeness and content quality.

final class ConfirmationCopyTests: XCTestCase {

    // MARK: — Catalog completeness

    func testAllActionsHaveNonEmptyStrings() {
        for action in ConfirmationCopy.Action.allCases {
            let copy = ConfirmationCopy.copy(for: action)
            XCTAssertFalse(copy.title.isEmpty,        "title must not be empty for \(action)")
            XCTAssertFalse(copy.body.isEmpty,         "body must not be empty for \(action)")
            XCTAssertFalse(copy.confirmLabel.isEmpty, "confirmLabel must not be empty for \(action)")
            XCTAssertFalse(copy.cancelLabel.isEmpty,  "cancelLabel must not be empty for \(action)")
        }
    }

    // MARK: — Destructive body pattern

    /// Delete/void/remove actions must mention permanence or irreversibility.
    func testDestructiveActionsBodyMentionsConsequence() {
        let destructiveActions: [ConfirmationCopy.Action] = [
            .deleteTicket, .deleteCustomer, .deleteInvoice,
            .deleteInventoryItem, .deleteExpense, .deleteAppointment,
            .deleteEmployee, .deleteLead, .deleteEstimate,
            .deleteNote, .voidInvoice
        ]
        let consequenceKeywords = ["permanently", "cannot be undone", "will be lost"]
        for action in destructiveActions {
            let body = ConfirmationCopy.copy(for: action).body.lowercased()
            let hasConsequence = consequenceKeywords.contains { body.contains($0) }
            XCTAssertTrue(hasConsequence,
                "body for \(action) must mention a consequence keyword; got: \"\(body)\"")
        }
    }

    // MARK: — Cancel label defaults

    func testMostActionsHaveCancelLabel() {
        // All actions except discardDraft use "Cancel"
        let nonDiscardActions = ConfirmationCopy.Action.allCases.filter { $0 != .discardDraft }
        for action in nonDiscardActions {
            let copy = ConfirmationCopy.copy(for: action)
            XCTAssertEqual(copy.cancelLabel, "Cancel",
                "cancelLabel should be 'Cancel' for \(action)")
        }
    }

    func testDiscardDraft_cancelLabelIsKeepEditing() {
        let copy = ConfirmationCopy.copy(for: .discardDraft)
        XCTAssertEqual(copy.cancelLabel, "Keep Editing")
    }

    // MARK: — Specific spot checks

    func testDeleteTicket_titleContainsTicket() {
        let copy = ConfirmationCopy.copy(for: .deleteTicket)
        XCTAssertTrue(copy.title.lowercased().contains("ticket"))
    }

    func testVoidInvoice_confirmLabelContainsVoid() {
        let copy = ConfirmationCopy.copy(for: .voidInvoice)
        XCTAssertTrue(copy.confirmLabel.lowercased().contains("void"))
    }

    func testArchiveTicket_bodyAllowsUnarchive() {
        // Archive is reversible — body should not say "cannot be undone"
        let copy = ConfirmationCopy.copy(for: .archiveTicket)
        XCTAssertFalse(copy.body.contains("cannot be undone"),
            "archive is reversible — body must not say 'cannot be undone'")
    }

    func testSignOut_confirmLabelIsSignOut() {
        let copy = ConfirmationCopy.copy(for: .signOut)
        XCTAssertEqual(copy.confirmLabel, "Sign Out")
    }

    // MARK: — Tone compliance

    func testAllCopiesPassToneGuidelines() {
        for action in ConfirmationCopy.Action.allCases {
            let copy = ConfirmationCopy.copy(for: action)
            let strings: [(String, String)] = [
                (copy.title,        "title(\(action))"),
                (copy.body,         "body(\(action))"),
                (copy.confirmLabel, "confirmLabel(\(action))"),
                (copy.cancelLabel,  "cancelLabel(\(action))")
            ]
            for (string, label) in strings {
                let violations = ToneGuidelines.violations(in: string)
                XCTAssertTrue(violations.isEmpty,
                    "\(label) has tone violations: \(violations) — \"\(string)\"")
            }
        }
    }
}
