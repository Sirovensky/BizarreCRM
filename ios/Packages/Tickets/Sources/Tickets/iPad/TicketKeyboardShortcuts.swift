import Foundation

// §22 — iPad keyboard shortcut ViewModifier for Tickets
//
// List shortcuts (always wired):
//   ⌘N   — new ticket (key: "n", modifiers: .command)
//   ⌘F   — focus search bar (key: "f", modifiers: .command)
//   ⌘R   — refresh list (key: "r", modifiers: .command)
//
// §4.13 action shortcuts (gated on isRowSelected):
//   ⌘D   — mark done (key: "d", modifiers: .command)
//   ⌘⇧A  — assign ticket (key: "a", modifiers: .command + .shift)
//   ⌘⇧S  — send SMS update (key: "s", modifiers: .command + .shift)
//   ⌘P   — print ticket (key: "p", modifiers: .command)
//   ⌘⌫   — delete ticket (key: backspace, modifiers: .command)
//
// Non-UI types are available on all platforms for testing.
// SwiftUI modifier (TicketKeyboardShortcuts) is UIKit-only.

// MARK: - Keyboard shortcut descriptor (platform-independent)

/// Stable descriptor for a single registered keyboard shortcut.
/// Tests validate keys + modifiers without importing SwiftUI.
public struct TicketKeyboardShortcutDescriptor: Sendable, Hashable {
    /// The character key (matches `KeyEquivalent` character).
    public let key: Character
    /// `.command`, `.shift`, etc.  Represented as raw `UInt` to avoid
    /// importing SwiftUI in non-UI targets.
    public let modifierFlags: UInt
    /// Human-readable label shown in the discoverability overlay.
    public let title: String

    public init(key: Character, modifierFlags: UInt, title: String) {
        self.key = key
        self.modifierFlags = modifierFlags
        self.title = title
    }
}

/// All shortcuts registered by `TicketKeyboardShortcuts`, in declaration order.
/// Used by tests to assert key bindings without constructing the SwiftUI modifier.
public enum TicketKeyboardShortcutRegistry {

    // EventModifierFlags raw values — hardcoded to avoid a SwiftUI import
    // in the pure-logic layer.
    private static let command: UInt  = 1_048_576          // 1 << 20
    private static let shift:   UInt  = 131_072             // 1 << 17
    private static let commandShift: UInt = command | shift

    public static let new = TicketKeyboardShortcutDescriptor(
        key: "n",
        modifierFlags: command,
        title: "New Ticket"
    )

    public static let search = TicketKeyboardShortcutDescriptor(
        key: "f",
        modifierFlags: command,
        title: "Search Tickets"
    )

    public static let refresh = TicketKeyboardShortcutDescriptor(
        key: "r",
        modifierFlags: command,
        title: "Refresh"
    )

    // §4.13 — iPad Magic Keyboard shortcuts for ticket actions

    /// ⌘D — mark the selected ticket done (advance to completion).
    public static let markDone = TicketKeyboardShortcutDescriptor(
        key: "d",
        modifierFlags: command,
        title: "Mark Done"
    )

    /// ⌘⇧A — open assignee picker for the selected ticket.
    public static let assign = TicketKeyboardShortcutDescriptor(
        key: "a",
        modifierFlags: commandShift,
        title: "Assign Ticket"
    )

    /// ⌘⇧S — send SMS status update to the customer.
    public static let sendSMS = TicketKeyboardShortcutDescriptor(
        key: "s",
        modifierFlags: commandShift,
        title: "Send SMS Update"
    )

    /// ⌘P — print / share work-order PDF.
    public static let print = TicketKeyboardShortcutDescriptor(
        key: "p",
        modifierFlags: command,
        title: "Print Ticket"
    )

    /// ⌘⌫ — delete the selected ticket (admin only, requires confirmation).
    public static let delete = TicketKeyboardShortcutDescriptor(
        key: "\u{08}",  // U+0008 = Backspace / Delete key
        modifierFlags: command,
        title: "Delete Ticket"
    )

    /// All registered shortcuts in declaration order.
    public static let all: [TicketKeyboardShortcutDescriptor] = [
        new, search, refresh, markDone, assign, sendSMS, print, delete
    ]
}

// MARK: - SwiftUI ViewModifier (UIKit-only)

#if canImport(UIKit)
import SwiftUI

/// Attaches Ticket keyboard shortcuts to any view.
///
/// The list shortcuts (⌘N / ⌘F / ⌘R) are always wired. The action shortcuts
/// (⌘D / ⌘⇧A / ⌘⇧S / ⌘P / ⌘⌫) are gated on `isRowSelected` — if no row is
/// selected they are no-ops so the OS sees them as unavailable and dims them in
/// the discoverability HUD.
///
/// ```swift
/// contentView
///     .modifier(TicketKeyboardShortcuts(
///         onNew:      { showingCreate = true },
///         onSearch:   { searchFocused = true },
///         onRefresh:  { Task { await vm.refresh() } },
///         onMarkDone: { Task { await vm.markSelectedDone() } },
///         onAssign:   { showingAssignee = true },
///         onSendSMS:  { vm.smsSelectedCustomer() },
///         onPrint:    { showingPrint = true },
///         onDelete:   { showingDeleteConfirm = true },
///         isRowSelected: selected != nil
///     ))
/// ```
public struct TicketKeyboardShortcuts: ViewModifier {

    public let onNew: () -> Void
    public let onSearch: () -> Void
    public let onRefresh: () -> Void
    /// §4.13 — ⌘D: mark selected ticket done.
    public let onMarkDone: () -> Void
    /// §4.13 — ⌘⇧A: open assignee picker.
    public let onAssign: () -> Void
    /// §4.13 — ⌘⇧S: SMS customer.
    public let onSendSMS: () -> Void
    /// §4.13 — ⌘P: print / share PDF.
    public let onPrint: () -> Void
    /// §4.13 — ⌘⌫: delete (admin only, requires confirmation).
    public let onDelete: () -> Void
    /// When false the action shortcuts are disabled in the discoverability HUD.
    public let isRowSelected: Bool

    public init(
        onNew: @escaping () -> Void,
        onSearch: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onMarkDone: @escaping () -> Void = {},
        onAssign: @escaping () -> Void = {},
        onSendSMS: @escaping () -> Void = {},
        onPrint: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {},
        isRowSelected: Bool = false
    ) {
        self.onNew = onNew
        self.onSearch = onSearch
        self.onRefresh = onRefresh
        self.onMarkDone = onMarkDone
        self.onAssign = onAssign
        self.onSendSMS = onSendSMS
        self.onPrint = onPrint
        self.onDelete = onDelete
        self.isRowSelected = isRowSelected
    }

    public func body(content: Content) -> some View {
        content
            // ⌘N — new ticket
            .background {
                Button("") { onNew() }
                    .keyboardShortcut(
                        KeyEquivalent(TicketKeyboardShortcutRegistry.new.key),
                        modifiers: .command
                    )
                    .accessibilityLabel(TicketKeyboardShortcutRegistry.new.title)
                    .accessibilityHint("Creates a new ticket")
                    .hidden()
            }
            // ⌘F — focus search
            .background {
                Button("") { onSearch() }
                    .keyboardShortcut(
                        KeyEquivalent(TicketKeyboardShortcutRegistry.search.key),
                        modifiers: .command
                    )
                    .accessibilityLabel(TicketKeyboardShortcutRegistry.search.title)
                    .accessibilityHint("Moves focus to the search field")
                    .hidden()
            }
            // ⌘R — refresh
            .background {
                Button("") { onRefresh() }
                    .keyboardShortcut(
                        KeyEquivalent(TicketKeyboardShortcutRegistry.refresh.key),
                        modifiers: .command
                    )
                    .accessibilityLabel(TicketKeyboardShortcutRegistry.refresh.title)
                    .accessibilityHint("Reloads the ticket list from the server")
                    .hidden()
            }
            // §4.13 — ⌘D: mark done (row must be selected)
            .background {
                Button("") { if isRowSelected { onMarkDone() } }
                    .keyboardShortcut(
                        KeyEquivalent(TicketKeyboardShortcutRegistry.markDone.key),
                        modifiers: .command
                    )
                    .accessibilityLabel(TicketKeyboardShortcutRegistry.markDone.title)
                    .accessibilityHint("Marks the selected ticket as done")
                    .disabled(!isRowSelected)
                    .hidden()
            }
            // §4.13 — ⌘⇧A: open assignee picker
            .background {
                Button("") { if isRowSelected { onAssign() } }
                    .keyboardShortcut(
                        KeyEquivalent(TicketKeyboardShortcutRegistry.assign.key),
                        modifiers: [.command, .shift]
                    )
                    .accessibilityLabel(TicketKeyboardShortcutRegistry.assign.title)
                    .accessibilityHint("Opens the assignee picker for the selected ticket")
                    .disabled(!isRowSelected)
                    .hidden()
            }
            // §4.13 — ⌘⇧S: send SMS to customer
            .background {
                Button("") { if isRowSelected { onSendSMS() } }
                    .keyboardShortcut(
                        KeyEquivalent(TicketKeyboardShortcutRegistry.sendSMS.key),
                        modifiers: [.command, .shift]
                    )
                    .accessibilityLabel(TicketKeyboardShortcutRegistry.sendSMS.title)
                    .accessibilityHint("Sends an SMS status update to the customer")
                    .disabled(!isRowSelected)
                    .hidden()
            }
            // §4.13 — ⌘P: print / share PDF
            .background {
                Button("") { if isRowSelected { onPrint() } }
                    .keyboardShortcut(
                        KeyEquivalent(TicketKeyboardShortcutRegistry.print.key),
                        modifiers: .command
                    )
                    .accessibilityLabel(TicketKeyboardShortcutRegistry.print.title)
                    .accessibilityHint("Prints or shares a PDF of the selected ticket")
                    .disabled(!isRowSelected)
                    .hidden()
            }
            // §4.13 — ⌘⌫: delete (requires confirmation; admin only)
            .background {
                Button("") { if isRowSelected { onDelete() } }
                    .keyboardShortcut(
                        KeyEquivalent(TicketKeyboardShortcutRegistry.delete.key),
                        modifiers: .command
                    )
                    .accessibilityLabel(TicketKeyboardShortcutRegistry.delete.title)
                    .accessibilityHint("Deletes the selected ticket after confirmation. Admin only.")
                    .disabled(!isRowSelected)
                    .hidden()
            }
    }
}

#endif
