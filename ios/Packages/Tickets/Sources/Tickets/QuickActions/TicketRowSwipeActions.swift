#if canImport(UIKit)
import SwiftUI
import Networking
import DesignSystem

// §22 + §4 — ViewModifier adding leading and trailing swipe actions to
// ticket list rows.
//
// Usage:
//   ticketRow
//       .modifier(TicketRowSwipeActions(ticket: ticket, handlers: handlers))

/// Adds `.swipeActions(edge: .trailing)` (Archive + Delete) and
/// `.swipeActions(edge: .leading)` (Advance Status + Assign) to any view.
///
/// §4 permission gates:
///   • Delete (trailing, destructive) — admin only.
///   • Archive (trailing) — manager+.
///   Pass `userRole: nil` to show all (backwards-compat).
public struct TicketRowSwipeActions: ViewModifier {
    public let ticket: TicketSummary
    public let currentStatus: TicketStatus?
    public let firstAssignee: TicketAssignee?
    public let handlers: TicketQuickActionHandlers
    /// Current user's role string from AuthMe.role. Nil = show all.
    public let userRole: String?

    public init(
        ticket: TicketSummary,
        currentStatus: TicketStatus?,
        firstAssignee: TicketAssignee? = nil,
        handlers: TicketQuickActionHandlers,
        userRole: String? = nil
    ) {
        self.ticket = ticket
        self.currentStatus = currentStatus
        self.firstAssignee = firstAssignee
        self.handlers = handlers
        self.userRole = userRole
    }

    private var isAdmin: Bool { userRole?.lowercased() == "admin" }
    private var isManagerOrAbove: Bool {
        let r = userRole?.lowercased() ?? ""
        return r == "admin" || r == "manager"
    }

    public func body(content: Content) -> some View {
        content
            // Trailing: Archive + Delete (permission-gated)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if isAdmin || userRole == nil {
                    Button(role: .destructive) {
                        handlers.onDelete(ticket)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .accessibilityLabel("Delete ticket")
                }

                if isManagerOrAbove || userRole == nil {
                    Button {
                        handlers.onArchive(ticket)
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .tint(Color.bizarreWarning)
                    .accessibilityLabel("Archive ticket")
                }
            }
            // Leading: Advance Status + SMS customer
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                if let status = currentStatus,
                   let firstTransition = TicketStateMachine.allowedTransitions(from: status).first {
                    Button {
                        handlers.onAdvanceStatus(ticket, firstTransition)
                    } label: {
                        Label(firstTransition.displayName, systemImage: firstTransition.systemImage)
                    }
                    .tint(Color.bizarreTeal)
                    .accessibilityLabel("Advance status: \(firstTransition.displayName)")
                }

                // §4.1 — SMS customer leading swipe
                if let phone = ticket.customer?.callablePhone,
                   let url = URL(string: "sms:\(phone.filter(\.isNumber))") {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        Label("SMS", systemImage: "message.fill")
                    }
                    .tint(Color.bizarreOrange)
                    .accessibilityLabel("SMS customer")
                } else if let assignee = firstAssignee {
                    Button {
                        handlers.onAssign(ticket, assignee.id)
                    } label: {
                        Label("Assign", systemImage: "person.badge.plus")
                    }
                    .tint(Color.bizarreOrange)
                    .accessibilityLabel("Assign to \(assignee.displayName)")
                }
            }
    }
}

#endif
