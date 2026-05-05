import SwiftUI
import Core
import Networking

// MARK: - LeadKeyboardShortcutAction

/// All keyboard-shortcut-driven actions for the Leads iPad layout.
public enum LeadKeyboardShortcutAction: Sendable {
    case newLead
    case search
    case refresh
    case convertSelected
    case archiveSelected
    case assignSelected
    case changeStatusSelected
    case nextLead
    case previousLead
}

// MARK: - LeadKeyboardShortcuts

/// Applies iPad keyboard shortcuts to the Leads three-column view.
///
/// Shortcuts:
/// - ⌘N            New lead
/// - ⌘F            Focus search
/// - ⌘R            Refresh list
/// - ⌘⇧C           Convert selected lead to customer
/// - ⌘⌫            Archive selected lead (mark lost)
/// - ⌘⇧A           Assign selected lead
/// - ⌘⇧S           Change status of selected lead
/// - ↑ / ↓         Navigate leads list (next / previous)
///
/// Usage: apply `.leadKeyboardShortcuts(onAction:)` to the root split view.
public struct LeadKeyboardShortcuts: ViewModifier {
    let onAction: (LeadKeyboardShortcutAction) -> Void

    public init(onAction: @escaping (LeadKeyboardShortcutAction) -> Void) {
        self.onAction = onAction
    }

    public func body(content: Content) -> some View {
        content
            // New lead
            .background(
                Group {
                    newLeadShortcut
                    searchShortcut
                    refreshShortcut
                    convertShortcut
                    archiveShortcut
                    assignShortcut
                    changeStatusShortcut
                    nextLeadShortcut
                    previousLeadShortcut
                }
            )
    }

    // MARK: - Individual shortcut views

    private var newLeadShortcut: some View {
        Button("New Lead") { onAction(.newLead) }
            .keyboardShortcut("n", modifiers: .command)
            .hidden()
            .accessibilityHidden(true)
    }

    private var searchShortcut: some View {
        Button("Search Leads") { onAction(.search) }
            .keyboardShortcut("f", modifiers: .command)
            .hidden()
            .accessibilityHidden(true)
    }

    private var refreshShortcut: some View {
        Button("Refresh Leads") { onAction(.refresh) }
            .keyboardShortcut("r", modifiers: .command)
            .hidden()
            .accessibilityHidden(true)
    }

    private var convertShortcut: some View {
        Button("Convert Lead") { onAction(.convertSelected) }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .hidden()
            .accessibilityHidden(true)
    }

    private var archiveShortcut: some View {
        Button("Archive Lead") { onAction(.archiveSelected) }
            .keyboardShortcut(.delete, modifiers: .command)
            .hidden()
            .accessibilityHidden(true)
    }

    private var assignShortcut: some View {
        Button("Assign Lead") { onAction(.assignSelected) }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .hidden()
            .accessibilityHidden(true)
    }

    private var changeStatusShortcut: some View {
        Button("Change Status") { onAction(.changeStatusSelected) }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .hidden()
            .accessibilityHidden(true)
    }

    private var nextLeadShortcut: some View {
        Button("Next Lead") { onAction(.nextLead) }
            .keyboardShortcut(.downArrow, modifiers: [])
            .hidden()
            .accessibilityHidden(true)
    }

    private var previousLeadShortcut: some View {
        Button("Previous Lead") { onAction(.previousLead) }
            .keyboardShortcut(.upArrow, modifiers: [])
            .hidden()
            .accessibilityHidden(true)
    }
}

// MARK: - View extension

public extension View {
    /// Attaches all standard Leads iPad keyboard shortcuts.
    func leadKeyboardShortcuts(
        onAction: @escaping (LeadKeyboardShortcutAction) -> Void
    ) -> some View {
        modifier(LeadKeyboardShortcuts(onAction: onAction))
    }
}

// MARK: - LeadShortcutDescription (for discoverability)

/// Static catalogue of all shortcuts — used by the Help / shortcut discovery UI.
public enum LeadShortcutDescriptions {
    public struct Entry: Sendable {
        public let title: String
        public let key: String
        public let modifiers: String
        public let action: LeadKeyboardShortcutAction
    }

    public static let all: [Entry] = [
        Entry(title: "New Lead",          key: "N", modifiers: "⌘",   action: .newLead),
        Entry(title: "Search",            key: "F", modifiers: "⌘",   action: .search),
        Entry(title: "Refresh",           key: "R", modifiers: "⌘",   action: .refresh),
        Entry(title: "Convert Lead",      key: "C", modifiers: "⌘⇧",  action: .convertSelected),
        Entry(title: "Archive Lead",      key: "⌫", modifiers: "⌘",   action: .archiveSelected),
        Entry(title: "Assign Lead",       key: "A", modifiers: "⌘⇧",  action: .assignSelected),
        Entry(title: "Change Status",     key: "S", modifiers: "⌘⇧",  action: .changeStatusSelected),
        Entry(title: "Next Lead",         key: "↓", modifiers: "",    action: .nextLead),
        Entry(title: "Previous Lead",     key: "↑", modifiers: "",    action: .previousLead),
    ]
}
