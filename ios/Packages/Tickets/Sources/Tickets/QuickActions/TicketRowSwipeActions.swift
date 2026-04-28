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
public struct TicketRowSwipeActions: ViewModifier {
    public let ticket: TicketSummary
    public let currentStatus: TicketStatus?
    public let firstAssignee: TicketAssignee?
    public let handlers: TicketQuickActionHandlers

    public init(
        ticket: TicketSummary,
        currentStatus: TicketStatus?,
        firstAssignee: TicketAssignee? = nil,
        handlers: TicketQuickActionHandlers
    ) {
        self.ticket = ticket
        self.currentStatus = currentStatus
        self.firstAssignee = firstAssignee
        self.handlers = handlers
    }

    public func body(content: Content) -> some View {
        content
            // Trailing: Mark complete + Archive
            // §4.1 spec: trailing = Archive / Mark complete
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    handlers.onArchive(ticket)
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .tint(Color.bizarreWarning)
                .accessibilityLabel("Archive ticket")

                // Mark complete: advance to the first "closed"-like transition if available.
                if let status = currentStatus {
                    let closingTransition = TicketStateMachine.allowedTransitions(from: status).first(where: {
                        let n = $0.displayName.lowercased()
                        return n.contains("complete") || n.contains("done") || n.contains("finish")
                    }) ?? TicketStateMachine.allowedTransitions(from: status).last
                    if let t = closingTransition {
                        Button {
                            handlers.onAdvanceStatus(ticket, t)
                        } label: {
                            Label("Mark Complete", systemImage: "checkmark.circle")
                        }
                        .tint(.green)
                        .accessibilityLabel("Mark ticket as \(t.displayName)")
                    }
                }
            }
            // Leading: Assign-to-me / SMS customer
            // §4.1 spec: leading = Assign-to-me / SMS customer
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
