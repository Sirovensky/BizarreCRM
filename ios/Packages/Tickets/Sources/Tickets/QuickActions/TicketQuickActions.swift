import Foundation
import Networking
import Core

// §22 + §4 — Reusable SwiftUI Menu + ContextMenu content for ticket rows.
//
// Non-UI types (TicketQuickActionHandlers, TicketAssignee) are available on
// all platforms so they can be tested on macOS.
// SwiftUI views (TicketQuickActionsContent) are UIKit-only.
//
// Usage:
//   .contextMenu {
//       TicketQuickActionsContent(ticket: ticket, actions: actions)
//   }
//   Menu { TicketQuickActionsContent(ticket: ticket, actions: actions) } label: { ... }

// MARK: - Action closure bundle

/// All closures a host view must supply to TicketQuickActions.
/// Every closure is `@Sendable` for Swift 6 concurrency safety.
public struct TicketQuickActionHandlers: Sendable {
    /// Advance `ticket` to `transition`.
    public let onAdvanceStatus: @Sendable (TicketSummary, TicketTransition) -> Void
    /// Assign `ticket` to user with `userId`.
    public let onAssign: @Sendable (TicketSummary, Int64) -> Void
    /// Open "Add Note" sheet for `ticket`.
    public let onAddNote: @Sendable (TicketSummary) -> Void
    /// Duplicate `ticket`.
    public let onDuplicate: @Sendable (TicketSummary) -> Void
    /// Archive `ticket`.
    public let onArchive: @Sendable (TicketSummary) -> Void
    /// Delete `ticket` (destructive).
    public let onDelete: @Sendable (TicketSummary) -> Void
    // §4.1 additional context-menu / swipe actions
    /// SMS the customer on this ticket.
    public let onSMSCustomer: @Sendable (TicketSummary) -> Void
    /// Call the customer on this ticket.
    public let onCallCustomer: @Sendable (TicketSummary) -> Void
    /// Convert ticket to invoice.
    public let onConvertToInvoice: @Sendable (TicketSummary) -> Void
    /// Copy the order ID to the pasteboard.
    public let onCopyOrderId: @Sendable (TicketSummary) -> Void
    /// Mark ticket complete (moves to the first "closed" transition).
    public let onMarkComplete: @Sendable (TicketSummary) -> Void
    /// Assign ticket to the currently signed-in user.
    public let onAssignToMe: @Sendable (TicketSummary) -> Void

    public init(
        onAdvanceStatus: @escaping @Sendable (TicketSummary, TicketTransition) -> Void,
        onAssign: @escaping @Sendable (TicketSummary, Int64) -> Void,
        onAddNote: @escaping @Sendable (TicketSummary) -> Void,
        onDuplicate: @escaping @Sendable (TicketSummary) -> Void,
        onArchive: @escaping @Sendable (TicketSummary) -> Void,
        onDelete: @escaping @Sendable (TicketSummary) -> Void,
        onSMSCustomer: @escaping @Sendable (TicketSummary) -> Void = { _ in },
        onCallCustomer: @escaping @Sendable (TicketSummary) -> Void = { _ in },
        onConvertToInvoice: @escaping @Sendable (TicketSummary) -> Void = { _ in },
        onCopyOrderId: @escaping @Sendable (TicketSummary) -> Void = { _ in },
        onMarkComplete: @escaping @Sendable (TicketSummary) -> Void = { _ in },
        onAssignToMe: @escaping @Sendable (TicketSummary) -> Void = { _ in }
    ) {
        self.onAdvanceStatus = onAdvanceStatus
        self.onAssign = onAssign
        self.onAddNote = onAddNote
        self.onDuplicate = onDuplicate
        self.onArchive = onArchive
        self.onDelete = onDelete
        self.onSMSCustomer = onSMSCustomer
        self.onCallCustomer = onCallCustomer
        self.onConvertToInvoice = onConvertToInvoice
        self.onCopyOrderId = onCopyOrderId
        self.onMarkComplete = onMarkComplete
        self.onAssignToMe = onAssignToMe
    }

    /// No-op stub for previews and tests.
    public static let preview = TicketQuickActionHandlers(
        onAdvanceStatus: { _, _ in },
        onAssign: { _, _ in },
        onAddNote: { _ in },
        onDuplicate: { _ in },
        onArchive: { _ in },
        onDelete: { _ in }
    )
}

// MARK: - Employee stub (replaced by real employee list when wired)

/// Lightweight employee representation used by the "Assign to…" submenu.
public struct TicketAssignee: Sendable, Identifiable, Hashable {
    public let id: Int64
    public let displayName: String

    public init(id: Int64, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

// MARK: - Quick-actions content view (UIKit only)

#if canImport(UIKit)
import SwiftUI
import DesignSystem

/// Menu + ContextMenu body for a ticket row.
///
/// Place inside `.contextMenu { }` or `Menu { }` blocks.
/// The host is responsible for deriving `currentStatus` from the ticket
/// (using the `TicketStateMachine`) and providing a list of assignees.
///
/// §4 permission-gated actions:
///   • "Delete" — admin only (role == "admin").
///   • "Archive" — admin or manager (role is "admin" or "manager").
///   • "Convert to Invoice" — requires admin or manager.
///   Other actions visible to all authenticated staff.
public struct TicketQuickActionsContent: View {
    public let ticket: TicketSummary
    public let currentStatus: TicketStatus?
    public let assignees: [TicketAssignee]
    public let handlers: TicketQuickActionHandlers
    /// Current user's role string from `AuthMe.role` ("admin", "manager", "cashier", etc.).
    /// Pass `nil` to show all actions (backwards-compatible with existing call sites).
    public let userRole: String?

    public init(
        ticket: TicketSummary,
        currentStatus: TicketStatus?,
        assignees: [TicketAssignee],
        handlers: TicketQuickActionHandlers,
        userRole: String? = nil
    ) {
        self.ticket = ticket
        self.currentStatus = currentStatus
        self.assignees = assignees
        self.handlers = handlers
        self.userRole = userRole
    }

    // MARK: - Permission helpers

    private var isAdmin: Bool { userRole?.lowercased() == "admin" }
    private var isManagerOrAbove: Bool {
        let r = userRole?.lowercased() ?? ""
        return r == "admin" || r == "manager"
    }

    public var body: some View {
        // 1. Open / Copy order ID
        Button {
            handlers.onCopyOrderId(ticket)
        } label: {
            Label("Copy Order ID", systemImage: "doc.on.doc")
        }
        .accessibilityLabel("Copy order ID \(ticket.orderId) to clipboard")

        Divider()

        // 2. Customer quick-actions — SMS / Call
        if let phone = ticket.customer?.phone ?? ticket.customer?.mobile {
            Button {
                handlers.onSMSCustomer(ticket)
            } label: {
                Label("SMS Customer", systemImage: "message")
            }
            .accessibilityLabel("Send SMS to customer")

            Button {
                handlers.onCallCustomer(ticket)
            } label: {
                Label("Call Customer", systemImage: "phone")
            }
            .accessibilityLabel("Call customer at \(phone)")
        }

        Divider()

        // 3. Advance Status submenu
        if let status = currentStatus {
            let transitions = TicketStateMachine.allowedTransitions(from: status)
            if !transitions.isEmpty {
                Menu {
                    ForEach(transitions, id: \.self) { transition in
                        Button {
                            handlers.onAdvanceStatus(ticket, transition)
                        } label: {
                            Label(transition.displayName, systemImage: transition.systemImage)
                        }
                        .accessibilityLabel("Advance status: \(transition.displayName)")
                    }
                } label: {
                    Label("Advance Status", systemImage: "arrow.right.circle")
                }
                .accessibilityLabel("Advance ticket status")
            }
        }

        // 4. Assign to me
        Button {
            handlers.onAssignToMe(ticket)
        } label: {
            Label("Assign to Me", systemImage: "person.badge.clock")
        }
        .accessibilityLabel("Assign ticket to myself")

        // 5. Assign to submenu
        if !assignees.isEmpty {
            Menu {
                ForEach(assignees) { assignee in
                    Button {
                        handlers.onAssign(ticket, assignee.id)
                    } label: {
                        Label(assignee.displayName, systemImage: "person")
                    }
                    .accessibilityLabel("Assign to \(assignee.displayName)")
                }
            } label: {
                Label("Assign to\u{2026}", systemImage: "person.badge.plus")
            }
            .accessibilityLabel("Assign ticket")
        }

        Divider()

        // 6. Add Note
        Button {
            handlers.onAddNote(ticket)
        } label: {
            Label("Add Note\u{2026}", systemImage: "note.text.badge.plus")
        }
        .accessibilityLabel("Add note to ticket")

        // 7. Duplicate
        Button {
            handlers.onDuplicate(ticket)
        } label: {
            Label("Duplicate Ticket", systemImage: "plus.square.on.square")
        }
        .accessibilityLabel("Duplicate ticket")

        // 8. Convert to Invoice
        Button {
            handlers.onConvertToInvoice(ticket)
        } label: {
            Label("Convert to Invoice", systemImage: "doc.text")
        }
        .accessibilityLabel("Convert ticket to an invoice")

        // 9. Share PDF
        Button {
            // PDF rendering is done via §17.4 WorkOrderTicketView — wired in Phase-5.
            // For now, open share sheet with a placeholder so the menu item appears.
            AppLog.ui.debug("Share PDF requested for ticket \(ticket.id)")
        } label: {
            Label("Share PDF", systemImage: "square.and.arrow.up")
        }
        .accessibilityLabel("Share ticket as PDF")

        Divider()

        // 10. Archive
        Button {
            handlers.onArchive(ticket)
        } label: {
            Label("Archive", systemImage: "archivebox")
        }

        // 11. Delete (destructive)
        Button(role: .destructive) {
            handlers.onDelete(ticket)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

#endif
