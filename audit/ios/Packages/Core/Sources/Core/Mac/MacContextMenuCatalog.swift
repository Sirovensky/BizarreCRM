// Core/Mac/MacContextMenuCatalog.swift
//
// Standard right-click menu items shared across BizarreCRM packages.
// Provides typed descriptors (no SwiftUI actions embedded) so each feature
// package can build a `contextMenu { … }` by mapping descriptors to its own
// callbacks — keeping this file free of feature-specific business logic.
//
// §23 Mac (Designed for iPad) polish — context menu catalog

import SwiftUI

// MARK: - MacContextMenuItem

/// A descriptor for a single context menu entry.
///
/// Descriptors are pure values — they carry a title, SF Symbol, and a role
/// hint, but no closure.  Feature packages map them to closures at the call
/// site, keeping this catalog testable without UI harness.
public struct MacContextMenuItem: Sendable, Equatable, Identifiable {
    public let id: String
    /// Display title shown in the context menu.
    public let title: String
    /// SF Symbol name for the leading icon.
    public let symbolName: String
    /// `ButtonRole` hint (e.g. `.destructive` for delete actions).
    public let role: MenuRole

    public init(
        id: String,
        title: String,
        symbolName: String,
        role: MenuRole = .none
    ) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.role = role
    }
}

// MARK: - MenuRole

/// Lightweight role tag for context menu items.
///
/// Mirrors the semantic intent of SwiftUI's `ButtonRole` without importing
/// it into the descriptor layer (ButtonRole is not Sendable / Equatable).
public enum MenuRole: Sendable, Equatable {
    /// No special role — standard action.
    case none
    /// Destructive — renders red on Mac and prompts confirmation on iOS.
    case destructive
    /// Cancel — dismisses the menu without performing an action.
    case cancel
}

// MARK: - MacContextMenuCatalog

/// Catalog of standard right-click (context) menu item descriptors shared
/// across BizarreCRM packages.
///
/// Usage:
/// ```swift
/// .contextMenu {
///     MacContextMenuCatalog.Actions.open.button { viewModel.openDetail() }
///     MacContextMenuCatalog.Actions.edit.button  { viewModel.beginEdit() }
///     Divider()
///     MacContextMenuCatalog.Actions.delete.button(role: .destructive) {
///         viewModel.delete()
///     }
/// }
/// ```
public enum MacContextMenuCatalog {

    // MARK: - General list-row actions

    public enum Actions {
        /// Open / view the selected item.
        public static let open = MacContextMenuItem(
            id: "ctx.open",
            title: "Open",
            symbolName: "arrow.up.right.square"
        )
        /// Begin editing the selected item.
        public static let edit = MacContextMenuItem(
            id: "ctx.edit",
            title: "Edit",
            symbolName: "pencil"
        )
        /// Duplicate the selected item.
        public static let duplicate = MacContextMenuItem(
            id: "ctx.duplicate",
            title: "Duplicate",
            symbolName: "plus.square.on.square"
        )
        /// Move the selected item to a different location.
        public static let move = MacContextMenuItem(
            id: "ctx.move",
            title: "Move",
            symbolName: "folder"
        )
        /// Share the selected item via the system share sheet.
        public static let share = MacContextMenuItem(
            id: "ctx.share",
            title: "Share",
            symbolName: "square.and.arrow.up"
        )
        /// Copy the selected item's primary identifier (ID, email …) to the clipboard.
        public static let copyID = MacContextMenuItem(
            id: "ctx.copyID",
            title: "Copy ID",
            symbolName: "doc.on.doc"
        )
        /// Archive the selected item (soft-delete / hide from active views).
        public static let archive = MacContextMenuItem(
            id: "ctx.archive",
            title: "Archive",
            symbolName: "archivebox"
        )
        /// Permanently delete the selected item.
        public static let delete = MacContextMenuItem(
            id: "ctx.delete",
            title: "Delete",
            symbolName: "trash",
            role: .destructive
        )
    }

    // MARK: - Ticket-specific

    public enum Tickets {
        /// Mark ticket as resolved.
        public static let markResolved = MacContextMenuItem(
            id: "ctx.tickets.markResolved",
            title: "Mark as Resolved",
            symbolName: "checkmark.circle"
        )
        /// Reassign the ticket to another technician.
        public static let reassign = MacContextMenuItem(
            id: "ctx.tickets.reassign",
            title: "Reassign",
            symbolName: "person.badge.plus"
        )
        /// Change ticket priority.
        public static let setPriority = MacContextMenuItem(
            id: "ctx.tickets.setPriority",
            title: "Set Priority",
            symbolName: "flag"
        )
    }

    // MARK: - Invoice-specific

    public enum Invoices {
        /// Mark invoice as paid.
        public static let markPaid = MacContextMenuItem(
            id: "ctx.invoices.markPaid",
            title: "Mark as Paid",
            symbolName: "checkmark.seal"
        )
        /// Send invoice via email.
        public static let sendByEmail = MacContextMenuItem(
            id: "ctx.invoices.sendByEmail",
            title: "Send by Email",
            symbolName: "envelope"
        )
        /// Print the invoice.
        public static let print = MacContextMenuItem(
            id: "ctx.invoices.print",
            title: "Print Invoice",
            symbolName: "printer"
        )
    }

    // MARK: - Customer-specific

    public enum Customers {
        /// Initiate a phone call to the customer.
        public static let call = MacContextMenuItem(
            id: "ctx.customers.call",
            title: "Call",
            symbolName: "phone"
        )
        /// Open SMS thread with the customer.
        public static let sendSMS = MacContextMenuItem(
            id: "ctx.customers.sendSMS",
            title: "Send SMS",
            symbolName: "message"
        )
        /// Compose an email to the customer.
        public static let sendEmail = MacContextMenuItem(
            id: "ctx.customers.sendEmail",
            title: "Send Email",
            symbolName: "envelope"
        )
    }

    // MARK: - All-items

    /// Flat list of all cataloged descriptors — useful for tests.
    public static let all: [MacContextMenuItem] = [
        Actions.open,
        Actions.edit,
        Actions.duplicate,
        Actions.move,
        Actions.share,
        Actions.copyID,
        Actions.archive,
        Actions.delete,
        Tickets.markResolved,
        Tickets.reassign,
        Tickets.setPriority,
        Invoices.markPaid,
        Invoices.sendByEmail,
        Invoices.print,
        Customers.call,
        Customers.sendSMS,
        Customers.sendEmail,
    ]
}

// MARK: - SwiftUI convenience

public extension MacContextMenuItem {
    /// Returns a SwiftUI `Button` that invokes `action` when tapped.
    ///
    /// ```swift
    /// .contextMenu {
    ///     MacContextMenuCatalog.Actions.delete.button { viewModel.delete() }
    /// }
    /// ```
    @ViewBuilder
    func button(action: @escaping () -> Void) -> some View {
        switch role {
        case .destructive:
            Button(role: .destructive, action: action) {
                Label(title, systemImage: symbolName)
            }
        case .cancel:
            Button(role: .cancel, action: action) {
                Label(title, systemImage: symbolName)
            }
        case .none:
            Button(action: action) {
                Label(title, systemImage: symbolName)
            }
        }
    }
}
