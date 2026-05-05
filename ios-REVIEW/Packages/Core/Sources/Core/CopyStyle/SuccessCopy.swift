import Foundation

// §64 — Post-action success banner copy.
//
// Design notes:
//  - All strings are NSLocalizedString-backed so §27 can translate.
//  - `message` is a short, complete sentence shown in a transient banner or toast.
//  - Banners are dismissible; no `title` is needed (the message IS the headline).
//  - Keep messages short — banners auto-dismiss after a few seconds.
//  - SF Symbol name is provided for an optional leading icon.
//  - Pure enum — no stored state, no side effects.

/// Canonical post-action success banner copy.
///
/// Usage:
/// ```swift
/// let copy = SuccessCopy.copy(for: .customerSaved)
/// banner.message   = copy.message
/// banner.symbol    = copy.symbolName
/// ```
public enum SuccessCopy {

    // MARK: — Event enum

    /// Post-action events for which a success banner is shown.
    public enum Event: Sendable, CaseIterable {
        case customerSaved
        case customerDeleted
        case ticketCreated
        case ticketSaved
        case ticketDeleted
        case ticketArchived
        case invoiceCreated
        case invoiceSaved
        case invoiceSent
        case invoicePaid
        case invoiceVoided
        case estimateSent
        case inventoryItemSaved
        case inventoryItemDeleted
        case expenseSaved
        case expenseDeleted
        case appointmentScheduled
        case appointmentSaved
        case appointmentDeleted
        case employeeSaved
        case employeeDeleted
        case noteSaved
        case noteDeleted
        case smsSent
        case passwordChanged
        case settingsSaved
        case dataCopied
        case reportExported
        case syncComplete
    }

    // MARK: — Per-event copy bundle

    public struct Copy: Sendable {
        /// Short success sentence shown in the banner, e.g. "Customer saved."
        public let message: String
        /// SF Symbol name for an optional leading icon.
        public let symbolName: String
    }

    // MARK: — Accessor

    /// Returns the `Copy` bundle for the given post-action event.
    public static func copy(for event: Event) -> Copy {
        switch event {
        case .customerSaved:
            return Copy(
                message: NSLocalizedString(
                    "success.customerSaved",
                    value: "Customer saved.",
                    comment: "Success banner — customer saved"
                ),
                symbolName: "person.fill.checkmark"
            )

        case .customerDeleted:
            return Copy(
                message: NSLocalizedString(
                    "success.customerDeleted",
                    value: "Customer deleted.",
                    comment: "Success banner — customer deleted"
                ),
                symbolName: "trash"
            )

        case .ticketCreated:
            return Copy(
                message: NSLocalizedString(
                    "success.ticketCreated",
                    value: "Ticket created.",
                    comment: "Success banner — ticket created"
                ),
                symbolName: "ticket.fill"
            )

        case .ticketSaved:
            return Copy(
                message: NSLocalizedString(
                    "success.ticketSaved",
                    value: "Ticket saved.",
                    comment: "Success banner — ticket saved"
                ),
                symbolName: "checkmark.circle.fill"
            )

        case .ticketDeleted:
            return Copy(
                message: NSLocalizedString(
                    "success.ticketDeleted",
                    value: "Ticket deleted.",
                    comment: "Success banner — ticket deleted"
                ),
                symbolName: "trash"
            )

        case .ticketArchived:
            return Copy(
                message: NSLocalizedString(
                    "success.ticketArchived",
                    value: "Ticket archived.",
                    comment: "Success banner — ticket archived"
                ),
                symbolName: "archivebox.fill"
            )

        case .invoiceCreated:
            return Copy(
                message: NSLocalizedString(
                    "success.invoiceCreated",
                    value: "Invoice created.",
                    comment: "Success banner — invoice created"
                ),
                symbolName: "doc.fill"
            )

        case .invoiceSaved:
            return Copy(
                message: NSLocalizedString(
                    "success.invoiceSaved",
                    value: "Invoice saved.",
                    comment: "Success banner — invoice saved"
                ),
                symbolName: "checkmark.circle.fill"
            )

        case .invoiceSent:
            return Copy(
                message: NSLocalizedString(
                    "success.invoiceSent",
                    value: "Invoice sent.",
                    comment: "Success banner — invoice sent"
                ),
                symbolName: "envelope.fill"
            )

        case .invoicePaid:
            return Copy(
                message: NSLocalizedString(
                    "success.invoicePaid",
                    value: "Payment recorded.",
                    comment: "Success banner — invoice paid"
                ),
                symbolName: "dollarsign.circle.fill"
            )

        case .invoiceVoided:
            return Copy(
                message: NSLocalizedString(
                    "success.invoiceVoided",
                    value: "Invoice voided.",
                    comment: "Success banner — invoice voided"
                ),
                symbolName: "xmark.circle.fill"
            )

        case .estimateSent:
            return Copy(
                message: NSLocalizedString(
                    "success.estimateSent",
                    value: "Estimate sent.",
                    comment: "Success banner — estimate sent"
                ),
                symbolName: "envelope.fill"
            )

        case .inventoryItemSaved:
            return Copy(
                message: NSLocalizedString(
                    "success.inventoryItemSaved",
                    value: "Item saved.",
                    comment: "Success banner — inventory item saved"
                ),
                symbolName: "checkmark.circle.fill"
            )

        case .inventoryItemDeleted:
            return Copy(
                message: NSLocalizedString(
                    "success.inventoryItemDeleted",
                    value: "Item deleted.",
                    comment: "Success banner — inventory item deleted"
                ),
                symbolName: "trash"
            )

        case .expenseSaved:
            return Copy(
                message: NSLocalizedString(
                    "success.expenseSaved",
                    value: "Expense saved.",
                    comment: "Success banner — expense saved"
                ),
                symbolName: "checkmark.circle.fill"
            )

        case .expenseDeleted:
            return Copy(
                message: NSLocalizedString(
                    "success.expenseDeleted",
                    value: "Expense deleted.",
                    comment: "Success banner — expense deleted"
                ),
                symbolName: "trash"
            )

        case .appointmentScheduled:
            return Copy(
                message: NSLocalizedString(
                    "success.appointmentScheduled",
                    value: "Appointment scheduled.",
                    comment: "Success banner — appointment scheduled"
                ),
                symbolName: "calendar.badge.checkmark"
            )

        case .appointmentSaved:
            return Copy(
                message: NSLocalizedString(
                    "success.appointmentSaved",
                    value: "Appointment saved.",
                    comment: "Success banner — appointment saved"
                ),
                symbolName: "checkmark.circle.fill"
            )

        case .appointmentDeleted:
            return Copy(
                message: NSLocalizedString(
                    "success.appointmentDeleted",
                    value: "Appointment deleted.",
                    comment: "Success banner — appointment deleted"
                ),
                symbolName: "trash"
            )

        case .employeeSaved:
            return Copy(
                message: NSLocalizedString(
                    "success.employeeSaved",
                    value: "Employee saved.",
                    comment: "Success banner — employee saved"
                ),
                symbolName: "person.fill.checkmark"
            )

        case .employeeDeleted:
            return Copy(
                message: NSLocalizedString(
                    "success.employeeDeleted",
                    value: "Employee removed.",
                    comment: "Success banner — employee deleted"
                ),
                symbolName: "person.fill.xmark"
            )

        case .noteSaved:
            return Copy(
                message: NSLocalizedString(
                    "success.noteSaved",
                    value: "Note saved.",
                    comment: "Success banner — note saved"
                ),
                symbolName: "note.text"
            )

        case .noteDeleted:
            return Copy(
                message: NSLocalizedString(
                    "success.noteDeleted",
                    value: "Note deleted.",
                    comment: "Success banner — note deleted"
                ),
                symbolName: "trash"
            )

        case .smsSent:
            return Copy(
                message: NSLocalizedString(
                    "success.smsSent",
                    value: "Message sent.",
                    comment: "Success banner — SMS sent"
                ),
                symbolName: "message.fill"
            )

        case .passwordChanged:
            return Copy(
                message: NSLocalizedString(
                    "success.passwordChanged",
                    value: "Password changed.",
                    comment: "Success banner — password changed"
                ),
                symbolName: "lock.fill"
            )

        case .settingsSaved:
            return Copy(
                message: NSLocalizedString(
                    "success.settingsSaved",
                    value: "Settings saved.",
                    comment: "Success banner — settings saved"
                ),
                symbolName: "checkmark.circle.fill"
            )

        case .dataCopied:
            return Copy(
                message: NSLocalizedString(
                    "success.dataCopied",
                    value: "Copied to clipboard.",
                    comment: "Success banner — data copied"
                ),
                symbolName: "doc.on.clipboard.fill"
            )

        case .reportExported:
            return Copy(
                message: NSLocalizedString(
                    "success.reportExported",
                    value: "Report exported.",
                    comment: "Success banner — report exported"
                ),
                symbolName: "square.and.arrow.up.fill"
            )

        case .syncComplete:
            return Copy(
                message: NSLocalizedString(
                    "success.syncComplete",
                    value: "Sync complete.",
                    comment: "Success banner — sync complete"
                ),
                symbolName: "arrow.triangle.2.circlepath"
            )
        }
    }
}
