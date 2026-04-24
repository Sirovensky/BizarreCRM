import Foundation

// §64 — Destructive action confirmation copy.
//
// Design notes:
//  - All strings are NSLocalizedString-backed so §27 can translate.
//  - `title` is a short question ("Delete ticket?").
//  - `body` begins with "This will permanently …" so the consequence is clear.
//  - `confirmLabel` is the destructive button label (red in SwiftUI .destructive role).
//  - `cancelLabel` is always "Cancel" for consistency.
//  - Pure enum — no stored state, no side effects.

/// Canonical copy for destructive action confirmation dialogs.
///
/// Usage:
/// ```swift
/// let copy = ConfirmationCopy.copy(for: .deleteTicket)
/// Alert(title: Text(copy.title),
///       message: Text(copy.body),
///       primaryButton: .destructive(Text(copy.confirmLabel)),
///       secondaryButton: .cancel(Text(copy.cancelLabel)))
/// ```
public enum ConfirmationCopy {

    // MARK: — Action enum

    /// Destructive actions that require user confirmation.
    public enum Action: Sendable, CaseIterable {
        case deleteTicket
        case deleteCustomer
        case deleteInvoice
        case deleteInventoryItem
        case deleteExpense
        case deleteAppointment
        case deleteEmployee
        case deleteLead
        case deleteEstimate
        case deleteNote
        case voidInvoice
        case archiveTicket
        case removeLineItem
        case discardDraft
        case signOut
    }

    // MARK: — Per-action copy bundle

    public struct Copy: Sendable {
        /// Short question headline, e.g. "Delete ticket?"
        public let title: String
        /// Full consequence sentence starting with "This will permanently …"
        public let body: String
        /// Label for the destructive confirm button.
        public let confirmLabel: String
        /// Label for the cancel button (always "Cancel").
        public let cancelLabel: String
    }

    // MARK: — Shared cancel label

    private static let cancel = NSLocalizedString(
        "confirm.cancel",
        value: "Cancel",
        comment: "Confirmation dialog — cancel button (shared)"
    )

    // MARK: — Accessor

    /// Returns the `Copy` bundle for the given destructive action.
    public static func copy(for action: Action) -> Copy {
        switch action {
        case .deleteTicket:
            return Copy(
                title: NSLocalizedString(
                    "confirm.deleteTicket.title",
                    value: "Delete ticket?",
                    comment: "Confirmation dialog — delete ticket title"
                ),
                body: NSLocalizedString(
                    "confirm.deleteTicket.body",
                    value: "This will permanently delete the ticket and all its notes. This action cannot be undone.",
                    comment: "Confirmation dialog — delete ticket body"
                ),
                confirmLabel: NSLocalizedString(
                    "confirm.deleteTicket.confirm",
                    value: "Delete Ticket",
                    comment: "Confirmation dialog — delete ticket confirm button"
                ),
                cancelLabel: cancel
            )

        case .deleteCustomer:
            return Copy(
                title: NSLocalizedString(
                    "confirm.deleteCustomer.title",
                    value: "Delete customer?",
                    comment: "Confirmation dialog — delete customer title"
                ),
                body: NSLocalizedString(
                    "confirm.deleteCustomer.body",
                    value: "This will permanently delete the customer record and all associated data. This action cannot be undone.",
                    comment: "Confirmation dialog — delete customer body"
                ),
                confirmLabel: NSLocalizedString(
                    "confirm.deleteCustomer.confirm",
                    value: "Delete Customer",
                    comment: "Confirmation dialog — delete customer confirm button"
                ),
                cancelLabel: cancel
            )

        case .deleteInvoice:
            return Copy(
                title: NSLocalizedString(
                    "confirm.deleteInvoice.title",
                    value: "Delete invoice?",
                    comment: "Confirmation dialog — delete invoice title"
                ),
                body: NSLocalizedString(
                    "confirm.deleteInvoice.body",
                    value: "This will permanently delete the invoice and its line items. This action cannot be undone.",
                    comment: "Confirmation dialog — delete invoice body"
                ),
                confirmLabel: NSLocalizedString(
                    "confirm.deleteInvoice.confirm",
                    value: "Delete Invoice",
                    comment: "Confirmation dialog — delete invoice confirm button"
                ),
                cancelLabel: cancel
            )

        case .deleteInventoryItem:
            return Copy(
                title: NSLocalizedString(
                    "confirm.deleteInventoryItem.title",
                    value: "Delete item?",
                    comment: "Confirmation dialog — delete inventory item title"
                ),
                body: NSLocalizedString(
                    "confirm.deleteInventoryItem.body",
                    value: "This will permanently delete the inventory item. Historical usage on tickets will remain. This action cannot be undone.",
                    comment: "Confirmation dialog — delete inventory item body"
                ),
                confirmLabel: NSLocalizedString(
                    "confirm.deleteInventoryItem.confirm",
                    value: "Delete Item",
                    comment: "Confirmation dialog — delete inventory item confirm button"
                ),
                cancelLabel: cancel
            )

        case .deleteExpense:
            return Copy(
                title: NSLocalizedString(
                    "confirm.deleteExpense.title",
                    value: "Delete expense?",
                    comment: "Confirmation dialog — delete expense title"
                ),
                body: NSLocalizedString(
                    "confirm.deleteExpense.body",
                    value: "This will permanently delete the expense record. This action cannot be undone.",
                    comment: "Confirmation dialog — delete expense body"
                ),
                confirmLabel: NSLocalizedString(
                    "confirm.deleteExpense.confirm",
                    value: "Delete Expense",
                    comment: "Confirmation dialog — delete expense confirm button"
                ),
                cancelLabel: cancel
            )

        case .deleteAppointment:
            return Copy(
                title: NSLocalizedString(
                    "confirm.deleteAppointment.title",
                    value: "Delete appointment?",
                    comment: "Confirmation dialog — delete appointment title"
                ),
                body: NSLocalizedString(
                    "confirm.deleteAppointment.body",
                    value: "This will permanently delete the appointment. The customer will not be notified automatically. This action cannot be undone.",
                    comment: "Confirmation dialog — delete appointment body"
                ),
                confirmLabel: NSLocalizedString(
                    "confirm.deleteAppointment.confirm",
                    value: "Delete Appointment",
                    comment: "Confirmation dialog — delete appointment confirm button"
                ),
                cancelLabel: cancel
            )

        case .deleteEmployee:
            return Copy(
                title: NSLocalizedString(
                    "confirm.deleteEmployee.title",
                    value: "Remove employee?",
                    comment: "Confirmation dialog — delete employee title"
                ),
                body: NSLocalizedString(
                    "confirm.deleteEmployee.body",
                    value: "This will permanently remove the employee and revoke their access. Historical records they created will remain. This action cannot be undone.",
                    comment: "Confirmation dialog — delete employee body"
                ),
                confirmLabel: NSLocalizedString(
                    "confirm.deleteEmployee.confirm",
                    value: "Remove Employee",
                    comment: "Confirmation dialog — delete employee confirm button"
                ),
                cancelLabel: cancel
            )

        case .deleteLead:
            return Copy(
                title: NSLocalizedString(
                    "confirm.deleteLead.title",
                    value: "Delete lead?",
                    comment: "Confirmation dialog — delete lead title"
                ),
                body: NSLocalizedString(
                    "confirm.deleteLead.body",
                    value: "This will permanently delete the lead. This action cannot be undone.",
                    comment: "Confirmation dialog — delete lead body"
                ),
                confirmLabel: NSLocalizedString(
                    "confirm.deleteLead.confirm",
                    value: "Delete Lead",
                    comment: "Confirmation dialog — delete lead confirm button"
                ),
                cancelLabel: cancel
            )

        case .deleteEstimate:
            return Copy(
                title: NSLocalizedString(
                    "confirm.deleteEstimate.title",
                    value: "Delete estimate?",
                    comment: "Confirmation dialog — delete estimate title"
                ),
                body: NSLocalizedString(
                    "confirm.deleteEstimate.body",
                    value: "This will permanently delete the estimate and its line items. This action cannot be undone.",
                    comment: "Confirmation dialog — delete estimate body"
                ),
                confirmLabel: NSLocalizedString(
                    "confirm.deleteEstimate.confirm",
                    value: "Delete Estimate",
                    comment: "Confirmation dialog — delete estimate confirm button"
                ),
                cancelLabel: cancel
            )

        case .deleteNote:
            return Copy(
                title: NSLocalizedString(
                    "confirm.deleteNote.title",
                    value: "Delete note?",
                    comment: "Confirmation dialog — delete note title"
                ),
                body: NSLocalizedString(
                    "confirm.deleteNote.body",
                    value: "This will permanently delete the note. This action cannot be undone.",
                    comment: "Confirmation dialog — delete note body"
                ),
                confirmLabel: NSLocalizedString(
                    "confirm.deleteNote.confirm",
                    value: "Delete Note",
                    comment: "Confirmation dialog — delete note confirm button"
                ),
                cancelLabel: cancel
            )

        case .voidInvoice:
            return Copy(
                title: NSLocalizedString(
                    "confirm.voidInvoice.title",
                    value: "Void invoice?",
                    comment: "Confirmation dialog — void invoice title"
                ),
                body: NSLocalizedString(
                    "confirm.voidInvoice.body",
                    value: "This will permanently void the invoice. The customer will no longer owe this amount. This action cannot be undone.",
                    comment: "Confirmation dialog — void invoice body"
                ),
                confirmLabel: NSLocalizedString(
                    "confirm.voidInvoice.confirm",
                    value: "Void Invoice",
                    comment: "Confirmation dialog — void invoice confirm button"
                ),
                cancelLabel: cancel
            )

        case .archiveTicket:
            return Copy(
                title: NSLocalizedString(
                    "confirm.archiveTicket.title",
                    value: "Archive ticket?",
                    comment: "Confirmation dialog — archive ticket title"
                ),
                body: NSLocalizedString(
                    "confirm.archiveTicket.body",
                    value: "This will move the ticket to the archive. You can unarchive it later if needed.",
                    comment: "Confirmation dialog — archive ticket body"
                ),
                confirmLabel: NSLocalizedString(
                    "confirm.archiveTicket.confirm",
                    value: "Archive Ticket",
                    comment: "Confirmation dialog — archive ticket confirm button"
                ),
                cancelLabel: cancel
            )

        case .removeLineItem:
            return Copy(
                title: NSLocalizedString(
                    "confirm.removeLineItem.title",
                    value: "Remove line item?",
                    comment: "Confirmation dialog — remove line item title"
                ),
                body: NSLocalizedString(
                    "confirm.removeLineItem.body",
                    value: "This will remove the line item from the invoice. The total will be recalculated.",
                    comment: "Confirmation dialog — remove line item body"
                ),
                confirmLabel: NSLocalizedString(
                    "confirm.removeLineItem.confirm",
                    value: "Remove",
                    comment: "Confirmation dialog — remove line item confirm button"
                ),
                cancelLabel: cancel
            )

        case .discardDraft:
            return Copy(
                title: NSLocalizedString(
                    "confirm.discardDraft.title",
                    value: "Discard changes?",
                    comment: "Confirmation dialog — discard draft title"
                ),
                body: NSLocalizedString(
                    "confirm.discardDraft.body",
                    value: "Your unsaved changes will be lost. This action cannot be undone.",
                    comment: "Confirmation dialog — discard draft body"
                ),
                confirmLabel: NSLocalizedString(
                    "confirm.discardDraft.confirm",
                    value: "Discard Changes",
                    comment: "Confirmation dialog — discard draft confirm button"
                ),
                cancelLabel: NSLocalizedString(
                    "confirm.discardDraft.cancel",
                    value: "Keep Editing",
                    comment: "Confirmation dialog — discard draft cancel button (custom)"
                )
            )

        case .signOut:
            return Copy(
                title: NSLocalizedString(
                    "confirm.signOut.title",
                    value: "Sign out?",
                    comment: "Confirmation dialog — sign out title"
                ),
                body: NSLocalizedString(
                    "confirm.signOut.body",
                    value: "You'll need to sign in again to access BizarreCRM.",
                    comment: "Confirmation dialog — sign out body"
                ),
                confirmLabel: NSLocalizedString(
                    "confirm.signOut.confirm",
                    value: "Sign Out",
                    comment: "Confirmation dialog — sign out confirm button"
                ),
                cancelLabel: cancel
            )
        }
    }
}
