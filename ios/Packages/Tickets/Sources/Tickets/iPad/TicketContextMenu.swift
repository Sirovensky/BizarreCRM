import Foundation
import Networking
#if canImport(UIKit)
import SwiftUI
import UIKit
#endif

// §22 — iPad context menu for ticket rows
//
// Provides the five required items:
//   1. Open              — navigate to ticket detail
//   2. Copy Ticket ID    — copy orderId to clipboard
//   3. Mark Complete     — advance to .completed via finishRepair → pickup chain
//   4. Archive           — archive the ticket
//   5. Delete            — destructive delete
//
// Non-UI types are available on all platforms so they can be tested on macOS.
// SwiftUI view (TicketContextMenu) is UIKit-only.

// MARK: - Context menu item identity (platform-independent)

/// Stable identifiers for the five required context menu items.
/// Used by tests to assert item presence without importing SwiftUI.
public enum TicketContextMenuItem: String, CaseIterable, Sendable, Hashable {
    case open            = "open"
    case copyId          = "copyId"
    case markComplete    = "markComplete"
    case archive         = "archive"
    case delete          = "delete"

    public var label: String {
        switch self {
        case .open:         return "Open"
        case .copyId:       return "Copy Ticket ID"
        case .markComplete: return "Mark Complete"
        case .archive:      return "Archive"
        case .delete:       return "Delete"
        }
    }

    public var systemImage: String {
        switch self {
        case .open:         return "arrow.up.right.square"
        case .copyId:       return "doc.on.doc"
        case .markComplete: return "checkmark.circle.fill"
        case .archive:      return "archivebox"
        case .delete:       return "trash"
        }
    }
}

// MARK: - SwiftUI context menu (UIKit-only)

#if canImport(UIKit)
import SwiftUI
import DesignSystem

/// Context menu body for an iPad ticket row.
///
/// Place directly inside `.contextMenu { }`:
///
/// ```swift
/// .contextMenu {
///     TicketContextMenu(ticket: ticket, currentStatus: status, handlers: handlers, onOpen: { ... })
/// }
/// ```
///
/// The menu renders five items in the required order:
///   Open / Copy ID / Mark Complete / Archive / Delete (destructive)
public struct TicketContextMenu: View {

    public let ticket: TicketSummary
    public let currentStatus: TicketStatus?
    public let handlers: TicketQuickActionHandlers
    public let onOpen: () -> Void

    public init(
        ticket: TicketSummary,
        currentStatus: TicketStatus?,
        handlers: TicketQuickActionHandlers,
        onOpen: @escaping () -> Void
    ) {
        self.ticket = ticket
        self.currentStatus = currentStatus
        self.handlers = handlers
        self.onOpen = onOpen
    }

    public var body: some View {
        // 1. Open
        Button {
            onOpen()
        } label: {
            Label(TicketContextMenuItem.open.label,
                  systemImage: TicketContextMenuItem.open.systemImage)
        }
        .accessibilityIdentifier("ticketMenu.open")

        // 2. Copy Ticket ID
        Button {
            UIPasteboard.general.string = ticket.orderId
        } label: {
            Label(TicketContextMenuItem.copyId.label,
                  systemImage: TicketContextMenuItem.copyId.systemImage)
        }
        .accessibilityIdentifier("ticketMenu.copyId")

        Divider()

        // 3. Mark Complete — fires the state machine's closest "complete" path.
        //    If status supports it directly, uses finishRepair; otherwise uses
        //    the generic advanceStatus handler with the most forward transition.
        Button {
            markComplete()
        } label: {
            Label(TicketContextMenuItem.markComplete.label,
                  systemImage: TicketContextMenuItem.markComplete.systemImage)
        }
        .disabled(isTerminal)
        .accessibilityIdentifier("ticketMenu.markComplete")
        .accessibilityLabel(TicketContextMenuItem.markComplete.label)
        .accessibilityHint(isTerminal ? "Ticket is already in a terminal state" : "Mark this ticket as complete")

        Divider()

        // 4. Archive
        Button {
            handlers.onArchive(ticket)
        } label: {
            Label(TicketContextMenuItem.archive.label,
                  systemImage: TicketContextMenuItem.archive.systemImage)
        }
        .accessibilityIdentifier("ticketMenu.archive")

        // 5. Delete (destructive)
        Button(role: .destructive) {
            handlers.onDelete(ticket)
        } label: {
            Label(TicketContextMenuItem.delete.label,
                  systemImage: TicketContextMenuItem.delete.systemImage)
        }
        .accessibilityIdentifier("ticketMenu.delete")
    }

    // MARK: - Helpers

    /// True when the current status is terminal (completed / canceled) and
    /// no further transitions are legal, so "Mark Complete" should be disabled.
    private var isTerminal: Bool {
        currentStatus?.isTerminal ?? false
    }

    /// Fire the most-forward available transition toward completion.
    /// Priority: finishRepair > pickup > first allowed non-cancel/hold.
    private func markComplete() {
        guard let status = currentStatus, !status.isTerminal else { return }
        let allowed = TicketStateMachine.allowedTransitions(from: status)
        let preferred: TicketTransition? =
            allowed.first(where: { $0 == .finishRepair })
            ?? allowed.first(where: { $0 == .pickup })
            ?? allowed.first(where: { $0 != .cancel && $0 != .hold })
        if let transition = preferred {
            handlers.onAdvanceStatus(ticket, transition)
        }
    }
}

#endif
