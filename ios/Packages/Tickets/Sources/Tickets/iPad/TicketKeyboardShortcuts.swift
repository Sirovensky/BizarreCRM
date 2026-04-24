import Foundation

// §22 — iPad keyboard shortcut ViewModifier for Tickets
//
// Three shortcuts:
//   ⌘N   — new ticket (key: "n", modifiers: .command)
//   ⌘F   — focus search bar (key: "f", modifiers: .command)
//   ⌘R   — refresh list (key: "r", modifiers: .command)
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

    // EventModifierFlags.command raw value (1 << 20 = 1_048_576)
    // Hardcoded to avoid a SwiftUI import in the pure-logic layer.
    private static let command: UInt = 1_048_576

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

    /// All registered shortcuts in declaration order.
    public static let all: [TicketKeyboardShortcutDescriptor] = [new, search, refresh]
}

// MARK: - SwiftUI ViewModifier (UIKit-only)

#if canImport(UIKit)
import SwiftUI

/// Attaches the three Ticket keyboard shortcuts to any view.
///
/// ```swift
/// contentView
///     .modifier(TicketKeyboardShortcuts(
///         onNew:     { showingCreate = true },
///         onSearch:  { searchFocused = true },
///         onRefresh: { Task { await vm.refresh() } }
///     ))
/// ```
public struct TicketKeyboardShortcuts: ViewModifier {

    public let onNew: () -> Void
    public let onSearch: () -> Void
    public let onRefresh: () -> Void

    public init(
        onNew: @escaping () -> Void,
        onSearch: @escaping () -> Void,
        onRefresh: @escaping () -> Void
    ) {
        self.onNew = onNew
        self.onSearch = onSearch
        self.onRefresh = onRefresh
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
    }
}

#endif
