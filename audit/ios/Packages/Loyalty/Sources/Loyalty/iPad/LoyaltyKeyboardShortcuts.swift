import SwiftUI

// MARK: - LoyaltyKeyboardShortcuts

/// §22 — Keyboard shortcut bindings for the iPad loyalty 3-col layout.
///
/// All four tier shortcuts use ⌘1–⌘4 (matching the sidebar order:
/// Bronze=1, Silver=2, Gold=3, Platinum=4).
/// Additional navigation shortcuts:
///  • ⌘R — refresh the current list.
///  • ⌘F — focus the search field.
///  • Esc — clear selection / deselect inspector.
///
/// Usage: attach `.loyaltyKeyboardShortcuts(...)` to `LoyaltyThreeColumnView`.
public extension View {
    /// Injects the full set of loyalty iPad keyboard shortcuts.
    func loyaltyKeyboardShortcuts(
        onSelectTier: @escaping (LoyaltyTier) -> Void,
        onRefresh: @escaping () -> Void,
        onFocusSearch: @escaping () -> Void,
        onClearSelection: @escaping () -> Void
    ) -> some View {
        modifier(LoyaltyKeyboardShortcutsModifier(
            onSelectTier: onSelectTier,
            onRefresh: onRefresh,
            onFocusSearch: onFocusSearch,
            onClearSelection: onClearSelection
        ))
    }
}

// MARK: - LoyaltyKeyboardShortcutsModifier

private struct LoyaltyKeyboardShortcutsModifier: ViewModifier {
    let onSelectTier: (LoyaltyTier) -> Void
    let onRefresh: () -> Void
    let onFocusSearch: () -> Void
    let onClearSelection: () -> Void

    func body(content: Content) -> some View {
        content
            // ⌘1 — Bronze
            .keyboardShortcut(KeyEquivalent("1"), modifiers: .command)
            .simultaneousGesture(
                TapGesture()
                    .onEnded { },
                including: .subviews
            )
            // Use overlay buttons for keyboard shortcuts (SwiftUI limitation:
            // .keyboardShortcut must be on a Button).
            .background(shortcutButtons)
    }

    private var shortcutButtons: some View {
        // Zero-size transparent buttons that capture keyboard shortcuts only.
        ZStack {
            // Tier selection ⌘1–⌘4
            ForEach(Array(LoyaltyTier.allCases.enumerated()), id: \.element) { idx, tier in
                Button("") { onSelectTier(tier) }
                    .keyboardShortcut(KeyEquivalent(Character(String(idx + 1))), modifiers: .command)
                    .accessibilityLabel("Select \(tier.displayName) tier")
                    .frame(width: 0, height: 0)
                    .opacity(0)
            }
            // ⌘R — refresh
            Button("") { onRefresh() }
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel("Refresh loyalty list")
                .frame(width: 0, height: 0)
                .opacity(0)
            // ⌘F — focus search
            Button("") { onFocusSearch() }
                .keyboardShortcut("f", modifiers: .command)
                .accessibilityLabel("Focus search")
                .frame(width: 0, height: 0)
                .opacity(0)
            // Esc — clear selection (macOS / hardware keyboard)
            Button("") { onClearSelection() }
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityLabel("Clear selection")
                .frame(width: 0, height: 0)
                .opacity(0)
        }
    }
}

// MARK: - LoyaltyShortcutDescriptions

/// Human-readable table of every loyalty keyboard shortcut.
///
/// Suitable for surfacing in a Help menu or `.commands` block.
public enum LoyaltyShortcutDescriptions {
    public struct Entry: Identifiable, Sendable {
        public let id: String
        public let key: String
        public let modifiers: String
        public let description: String
    }

    public static let all: [Entry] = [
        Entry(id: "bronze",  key: "1", modifiers: "⌘",  description: "Select Bronze tier"),
        Entry(id: "silver",  key: "2", modifiers: "⌘",  description: "Select Silver tier"),
        Entry(id: "gold",    key: "3", modifiers: "⌘",  description: "Select Gold tier"),
        Entry(id: "platinum",key: "4", modifiers: "⌘",  description: "Select Platinum tier"),
        Entry(id: "refresh", key: "R", modifiers: "⌘",  description: "Refresh member list"),
        Entry(id: "search",  key: "F", modifiers: "⌘",  description: "Focus search field"),
        Entry(id: "clear",   key: "Esc", modifiers: "", description: "Clear inspector selection"),
    ]
}
