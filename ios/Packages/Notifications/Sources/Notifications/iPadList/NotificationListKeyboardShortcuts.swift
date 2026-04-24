import SwiftUI

// MARK: - NotificationListKeyboardShortcuts
//
// §22 iPad — keyboard shortcut bindings for the notification list.
//
// Shortcuts:
//   ⌘1 … ⌘5   — switch sidebar category (All / Unread / Flagged / Pinned / Archived)
//   j           — navigate to next notification (vi-style)
//   k           — navigate to previous notification (vi-style)
//   ⌘R          — force refresh list
//
// Implemented as a ViewModifier so any containing view can attach it once.

// MARK: - NotificationListKeyboardShortcutsModifier

struct NotificationListKeyboardShortcutsModifier: ViewModifier {

    // MARK: - Callbacks

    let onCategoryChange: (NotificationSidebarCategory) -> Void
    let onNavigateUp: () -> Void
    let onNavigateDown: () -> Void
    let onRefresh: () -> Void

    // MARK: - Body

    func body(content: Content) -> some View {
        content
            .background(shortcutButtons)
    }

    // MARK: - Shortcut buttons (hidden, keyboard-only)
    // Following the DataExportShortcutModifier pattern: hidden Button views with
    // .keyboardShortcut bindings, surfaced in the SwiftUI commands graph.

    private var shortcutButtons: some View {
        Group {
            // ⌘1 … ⌘5 — sidebar categories
            Button("All") { onCategoryChange(.all) }
                .keyboardShortcut(NotificationSidebarCategory.all.keyboardShortcut, modifiers: .command)
                .accessibilityHidden(true)
                .accessibilityIdentifier("notif.ipad.kbd.category.all")

            Button("Unread") { onCategoryChange(.unread) }
                .keyboardShortcut(NotificationSidebarCategory.unread.keyboardShortcut, modifiers: .command)
                .accessibilityHidden(true)
                .accessibilityIdentifier("notif.ipad.kbd.category.unread")

            Button("Flagged") { onCategoryChange(.flagged) }
                .keyboardShortcut(NotificationSidebarCategory.flagged.keyboardShortcut, modifiers: .command)
                .accessibilityHidden(true)
                .accessibilityIdentifier("notif.ipad.kbd.category.flagged")

            Button("Pinned") { onCategoryChange(.pinned) }
                .keyboardShortcut(NotificationSidebarCategory.pinned.keyboardShortcut, modifiers: .command)
                .accessibilityHidden(true)
                .accessibilityIdentifier("notif.ipad.kbd.category.pinned")

            Button("Archived") { onCategoryChange(.archived) }
                .keyboardShortcut(NotificationSidebarCategory.archived.keyboardShortcut, modifiers: .command)
                .accessibilityHidden(true)
                .accessibilityIdentifier("notif.ipad.kbd.category.archived")

            // ⌘R — refresh
            Button("Refresh") { onRefresh() }
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityHidden(true)
                .accessibilityIdentifier("notif.ipad.kbd.refresh")

            // j / k — vi-style list navigation (no modifier)
            Button("Navigate Down") { onNavigateDown() }
                .keyboardShortcut("j", modifiers: [])
                .accessibilityHidden(true)
                .accessibilityIdentifier("notif.ipad.kbd.navDown")

            Button("Navigate Up") { onNavigateUp() }
                .keyboardShortcut("k", modifiers: [])
                .accessibilityHidden(true)
                .accessibilityIdentifier("notif.ipad.kbd.navUp")
        }
        .frame(width: 0, height: 0)
        .hidden()
    }
}

// MARK: - View extension

public extension View {
    /// Attach iPad notification keyboard shortcuts to any view.
    ///
    /// - Parameters:
    ///   - onCategoryChange: Called with the new `NotificationSidebarCategory` when ⌘1…⌘5 fires.
    ///   - onNavigateUp: Called when `k` is pressed (move selection up).
    ///   - onNavigateDown: Called when `j` is pressed (move selection down).
    ///   - onRefresh: Called when ⌘R is pressed.
    func notificationListKeyboardShortcuts(
        onCategoryChange: @escaping (NotificationSidebarCategory) -> Void,
        onNavigateUp: @escaping () -> Void,
        onNavigateDown: @escaping () -> Void,
        onRefresh: @escaping () -> Void
    ) -> some View {
        modifier(NotificationListKeyboardShortcutsModifier(
            onCategoryChange: onCategoryChange,
            onNavigateUp: onNavigateUp,
            onNavigateDown: onNavigateDown,
            onRefresh: onRefresh
        ))
    }
}

// MARK: - NotificationKeyboardShortcutSpec
//
// Value type describing one shortcut. Used in tests and documentation.

public struct NotificationKeyboardShortcutSpec: Sendable, Equatable {
    public let key: Character
    public let modifiers: EventModifiers
    public let description: String

    public init(key: Character, modifiers: EventModifiers, description: String) {
        self.key = key
        self.modifiers = modifiers
        self.description = description
    }

    /// All defined notification list keyboard shortcuts, in documentation order.
    public static let all: [NotificationKeyboardShortcutSpec] = [
        .init(key: "1", modifiers: .command, description: "Switch to All category"),
        .init(key: "2", modifiers: .command, description: "Switch to Unread category"),
        .init(key: "3", modifiers: .command, description: "Switch to Flagged category"),
        .init(key: "4", modifiers: .command, description: "Switch to Pinned category"),
        .init(key: "5", modifiers: .command, description: "Switch to Archived category"),
        .init(key: "j", modifiers: [],        description: "Navigate to next notification"),
        .init(key: "k", modifiers: [],        description: "Navigate to previous notification"),
        .init(key: "r", modifiers: .command,  description: "Refresh notification list"),
    ]
}
