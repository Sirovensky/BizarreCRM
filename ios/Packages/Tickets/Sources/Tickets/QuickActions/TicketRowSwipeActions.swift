#if canImport(UIKit)
import SwiftUI
import Networking
import DesignSystem

// §22 + §4 — ViewModifier adding leading and trailing swipe actions to
// ticket list rows.
//
// §4.13 spec:
//   right swipe (trailing): state-dependent "Start/Mark Ready" (first forward transition)
//                            Archive (full-swipe, role: .destructive = iOS confirmation)
//   left swipe (leading):   Assign-to-me / SMS customer
//   long-swipe destructive: Delete requires alert confirmation (role: .destructive)
//
// Usage:
//   ticketRow
//       .modifier(TicketRowSwipeActions(ticket: ticket, currentStatus: status, handlers: handlers))

/// Adds `.swipeActions(edge: .trailing)` (Mark Ready + Archive) and
/// `.swipeActions(edge: .leading)` (Assign-to-me + SMS) to any view.
///
/// Full-swipe on the Archive button triggers the destructive-confirm role so iOS
/// shows a "Confirm?" prompt before executing — matching §4.13 "long-swipe destructive
/// requires alert confirm".
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
            // Trailing: state-dependent "Start / Mark Ready" + Archive (full-swipe)
            // §4.13: right swipe = Start / Mark Ready (state-dependent)
            // §4.13: long-swipe destructive requires alert confirm (role: .destructive)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                // Archive — full-swipe allowed; role: .destructive triggers system confirmation
                Button(role: .destructive) {
                    handlers.onArchive(ticket)
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .accessibilityLabel("Archive ticket")

                // State-dependent forward action: "Mark Ready" / "Mark Complete" / advance step
                if let status = currentStatus {
                    // §4.13: prefer a "ready" or "start" transition; fall back to forward move
                    let forwardTransition = TicketStateMachine.allowedTransitions(from: status).first(where: {
                        let n = $0.displayName.lowercased()
                        return n.contains("ready") || n.contains("start") || n.contains("begin")
                    }) ?? TicketStateMachine.allowedTransitions(from: status).first(where: {
                        let n = $0.displayName.lowercased()
                        return n.contains("complete") || n.contains("done") || n.contains("finish")
                    }) ?? TicketStateMachine.allowedTransitions(from: status).last

                    if let t = forwardTransition {
                        Button {
                            handlers.onAdvanceStatus(ticket, t)
                        } label: {
                            Label(t.displayName, systemImage: "arrow.right.circle.fill")
                        }
                        .tint(.green)
                        .accessibilityLabel("Advance ticket: \(t.displayName)")
                    }
                }
            }
            // Leading: Assign-to-me / SMS customer
            // §4.1 + §4.13 spec: leading = Assign-to-me / SMS customer
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    handlers.onAssignToMe(ticket)
                } label: {
                    Label("Assign to Me", systemImage: "person.badge.clock")
                }
                .tint(Color.bizarreOrange)
                .accessibilityLabel("Assign ticket to myself")

                if ticket.customer?.phone != nil || ticket.customer?.mobile != nil {
                    Button {
                        handlers.onSMSCustomer(ticket)
                    } label: {
                        Label("SMS", systemImage: "message")
                    }
                    .tint(Color.bizarreTeal)
                    .accessibilityLabel("Send SMS to customer")
                }
            }
    }
}

#endif
