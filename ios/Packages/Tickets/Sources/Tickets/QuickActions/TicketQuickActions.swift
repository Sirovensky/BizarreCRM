import Foundation
import Networking

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

    public init(
        onAdvanceStatus: @escaping @Sendable (TicketSummary, TicketTransition) -> Void,
        onAssign: @escaping @Sendable (TicketSummary, Int64) -> Void,
        onAddNote: @escaping @Sendable (TicketSummary) -> Void,
        onDuplicate: @escaping @Sendable (TicketSummary) -> Void,
        onArchive: @escaping @Sendable (TicketSummary) -> Void,
        onDelete: @escaping @Sendable (TicketSummary) -> Void
    ) {
        self.onAdvanceStatus = onAdvanceStatus
        self.onAssign = onAssign
        self.onAddNote = onAddNote
        self.onDuplicate = onDuplicate
        self.onArchive = onArchive
        self.onDelete = onDelete
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
public struct TicketQuickActionsContent: View {
    public let ticket: TicketSummary
    public let currentStatus: TicketStatus?
    public let assignees: [TicketAssignee]
    public let handlers: TicketQuickActionHandlers

    public init(
        ticket: TicketSummary,
        currentStatus: TicketStatus?,
        assignees: [TicketAssignee],
        handlers: TicketQuickActionHandlers
    ) {
        self.ticket = ticket
        self.currentStatus = currentStatus
        self.assignees = assignees
        self.handlers = handlers
    }

    public var body: some View {
        // 1. Advance Status submenu
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

        // 2. Assign to submenu
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

        // 3. Add Note
        Button {
            handlers.onAddNote(ticket)
        } label: {
            Label("Add Note\u{2026}", systemImage: "note.text.badge.plus")
        }
        .accessibilityLabel("Add note to ticket")

        // 4. Duplicate
        Button {
            handlers.onDuplicate(ticket)
        } label: {
            Label("Duplicate Ticket", systemImage: "plus.square.on.square")
        }
        .accessibilityLabel("Duplicate ticket")

        Divider()

        // 5. Archive
        Button {
            handlers.onArchive(ticket)
        } label: {
            Label("Archive", systemImage: "archivebox")
        }
        .accessibilityLabel("Archive ticket")

        // 6. Delete (destructive)
        Button(role: .destructive) {
            handlers.onDelete(ticket)
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .accessibilityLabel("Delete ticket")
    }
}

#endif
