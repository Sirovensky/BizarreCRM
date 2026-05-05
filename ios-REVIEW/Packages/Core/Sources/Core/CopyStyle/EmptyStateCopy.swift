import Foundation

// §64 — Per-entity empty-state messages.
//
// Design notes:
//  - All strings are NSLocalizedString-backed so §27 can translate.
//  - Each entity has a `title` (short headline) and `body` (friendly prompt with a CTA hint).
//  - A `createLabel` is provided for entities that support creation from the empty state.
//  - Organized by entity; add new cases at the bottom of `Entity`.
//  - Pure enum — no stored state, no side effects.

/// Canonical empty-state copy for each CRM entity.
///
/// Usage:
/// ```swift
/// let copy = EmptyStateCopy.copy(for: .tickets)
/// headline.text = copy.title
/// detail.text   = copy.body
/// if let label = copy.createLabel {
///     createButton.setTitle(label, for: .normal)
/// }
/// ```
public enum EmptyStateCopy {

    // MARK: — Entity enum

    /// CRM entity for which an empty state can be shown.
    public enum Entity: Sendable, CaseIterable {
        case tickets
        case customers
        case invoices
        case inventory
        case expenses
        case appointments
        case employees
        case leads
        case estimates
        case auditLogs
        case smsConversations
        case searchResults
        case notifications
        case reports
    }

    // MARK: — Per-entity copy bundle

    public struct Copy: Sendable {
        /// Short headline, e.g. "No tickets yet."
        public let title: String
        /// Friendly body with a gentle call-to-action hint.
        public let body: String
        /// Label for a primary create/add button, or `nil` when creation is not offered here.
        public let createLabel: String?
    }

    // MARK: — Accessor

    /// Returns the `Copy` bundle for the given entity.
    public static func copy(for entity: Entity) -> Copy {
        switch entity {
        case .tickets:
            return Copy(
                title: NSLocalizedString(
                    "empty.tickets.title",
                    value: "No tickets yet.",
                    comment: "Empty state — tickets list title"
                ),
                body: NSLocalizedString(
                    "empty.tickets.body",
                    value: "Start by creating a ticket for a customer's device.",
                    comment: "Empty state — tickets list body"
                ),
                createLabel: NSLocalizedString(
                    "empty.tickets.create",
                    value: "Create Ticket",
                    comment: "Empty state — tickets list create button"
                )
            )

        case .customers:
            return Copy(
                title: NSLocalizedString(
                    "empty.customers.title",
                    value: "No customers yet.",
                    comment: "Empty state — customers list title"
                ),
                body: NSLocalizedString(
                    "empty.customers.body",
                    value: "Add your first customer to get started.",
                    comment: "Empty state — customers list body"
                ),
                createLabel: NSLocalizedString(
                    "empty.customers.create",
                    value: "Add Customer",
                    comment: "Empty state — customers list create button"
                )
            )

        case .invoices:
            return Copy(
                title: NSLocalizedString(
                    "empty.invoices.title",
                    value: "No invoices yet.",
                    comment: "Empty state — invoices list title"
                ),
                body: NSLocalizedString(
                    "empty.invoices.body",
                    value: "Create an invoice when a job is ready to bill.",
                    comment: "Empty state — invoices list body"
                ),
                createLabel: NSLocalizedString(
                    "empty.invoices.create",
                    value: "Create Invoice",
                    comment: "Empty state — invoices list create button"
                )
            )

        case .inventory:
            return Copy(
                title: NSLocalizedString(
                    "empty.inventory.title",
                    value: "No items in inventory.",
                    comment: "Empty state — inventory list title"
                ),
                body: NSLocalizedString(
                    "empty.inventory.body",
                    value: "Add parts and supplies to track your stock.",
                    comment: "Empty state — inventory list body"
                ),
                createLabel: NSLocalizedString(
                    "empty.inventory.create",
                    value: "Add Item",
                    comment: "Empty state — inventory list create button"
                )
            )

        case .expenses:
            return Copy(
                title: NSLocalizedString(
                    "empty.expenses.title",
                    value: "No expenses recorded.",
                    comment: "Empty state — expenses list title"
                ),
                body: NSLocalizedString(
                    "empty.expenses.body",
                    value: "Log an expense to keep your books accurate.",
                    comment: "Empty state — expenses list body"
                ),
                createLabel: NSLocalizedString(
                    "empty.expenses.create",
                    value: "Log Expense",
                    comment: "Empty state — expenses list create button"
                )
            )

        case .appointments:
            return Copy(
                title: NSLocalizedString(
                    "empty.appointments.title",
                    value: "No appointments scheduled.",
                    comment: "Empty state — appointments list title"
                ),
                body: NSLocalizedString(
                    "empty.appointments.body",
                    value: "Schedule an appointment to block time for a customer.",
                    comment: "Empty state — appointments list body"
                ),
                createLabel: NSLocalizedString(
                    "empty.appointments.create",
                    value: "Schedule Appointment",
                    comment: "Empty state — appointments list create button"
                )
            )

        case .employees:
            return Copy(
                title: NSLocalizedString(
                    "empty.employees.title",
                    value: "No employees added.",
                    comment: "Empty state — employees list title"
                ),
                body: NSLocalizedString(
                    "empty.employees.body",
                    value: "Add team members to assign tickets and track hours.",
                    comment: "Empty state — employees list body"
                ),
                createLabel: NSLocalizedString(
                    "empty.employees.create",
                    value: "Add Employee",
                    comment: "Empty state — employees list create button"
                )
            )

        case .leads:
            return Copy(
                title: NSLocalizedString(
                    "empty.leads.title",
                    value: "No leads yet.",
                    comment: "Empty state — leads list title"
                ),
                body: NSLocalizedString(
                    "empty.leads.body",
                    value: "Capture a lead to follow up with potential customers.",
                    comment: "Empty state — leads list body"
                ),
                createLabel: NSLocalizedString(
                    "empty.leads.create",
                    value: "Add Lead",
                    comment: "Empty state — leads list create button"
                )
            )

        case .estimates:
            return Copy(
                title: NSLocalizedString(
                    "empty.estimates.title",
                    value: "No estimates yet.",
                    comment: "Empty state — estimates list title"
                ),
                body: NSLocalizedString(
                    "empty.estimates.body",
                    value: "Send an estimate before converting it to an invoice.",
                    comment: "Empty state — estimates list body"
                ),
                createLabel: NSLocalizedString(
                    "empty.estimates.create",
                    value: "Create Estimate",
                    comment: "Empty state — estimates list create button"
                )
            )

        case .auditLogs:
            return Copy(
                title: NSLocalizedString(
                    "empty.auditLogs.title",
                    value: "No activity yet.",
                    comment: "Empty state — audit log list title"
                ),
                body: NSLocalizedString(
                    "empty.auditLogs.body",
                    value: "Actions taken in the app will appear here.",
                    comment: "Empty state — audit log list body"
                ),
                createLabel: nil
            )

        case .smsConversations:
            return Copy(
                title: NSLocalizedString(
                    "empty.sms.title",
                    value: "No messages yet.",
                    comment: "Empty state — SMS conversation list title"
                ),
                body: NSLocalizedString(
                    "empty.sms.body",
                    value: "Send a message to start a conversation with a customer.",
                    comment: "Empty state — SMS conversation list body"
                ),
                createLabel: NSLocalizedString(
                    "empty.sms.create",
                    value: "New Message",
                    comment: "Empty state — SMS conversation list create button"
                )
            )

        case .searchResults:
            return Copy(
                title: NSLocalizedString(
                    "empty.search.title",
                    value: "No results found.",
                    comment: "Empty state — search results title"
                ),
                body: NSLocalizedString(
                    "empty.search.body",
                    value: "Try a different search term or check for typos.",
                    comment: "Empty state — search results body"
                ),
                createLabel: nil
            )

        case .notifications:
            return Copy(
                title: NSLocalizedString(
                    "empty.notifications.title",
                    value: "All caught up.",
                    comment: "Empty state — notifications list title"
                ),
                body: NSLocalizedString(
                    "empty.notifications.body",
                    value: "You have no new notifications.",
                    comment: "Empty state — notifications list body"
                ),
                createLabel: nil
            )

        case .reports:
            return Copy(
                title: NSLocalizedString(
                    "empty.reports.title",
                    value: "No data to show.",
                    comment: "Empty state — reports title"
                ),
                body: NSLocalizedString(
                    "empty.reports.body",
                    value: "Try adjusting the date range or filters.",
                    comment: "Empty state — reports body"
                ),
                createLabel: nil
            )
        }
    }
}
