import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - EstimateKeyboardShortcuts
//
// §22 — iPad keyboard shortcuts for the Estimates three-column layout.
//
// Shortcuts:
//   ⌘N   — New Estimate (presents create form)
//   ⌘F   — Focus search field
//   ⌘R   — Refresh list
//   ⌘⇧S  — Send for Signature (on selected estimate)
//
// Attach via .estimateKeyboardShortcuts(...) on EstimatesThreeColumnView.

#if canImport(UIKit)

// MARK: - View Modifier

struct EstimateKeyboardShortcutsModifier: ViewModifier {

    /// Called when ⌘N fires; caller presents the create sheet.
    let onNew: () -> Void
    /// Called when ⌘F fires; caller focuses its search field.
    let onFocusSearch: () -> Void
    /// Called when ⌘R fires; caller triggers a refresh.
    let onRefresh: () -> Void
    /// Called when ⌘⇧S fires; caller presents the sign sheet for the selected estimate.
    let onSendForSignature: () -> Void

    func body(content: Content) -> some View {
        content
            // ⌘N — New Estimate
            .background(
                Button("") { onNew() }
                    .keyboardShortcut("n", modifiers: .command)
                    .accessibilityHidden(true)
                    .frame(width: 0, height: 0)
                    .opacity(0)
            )
            // ⌘F — Focus Search
            .background(
                Button("") { onFocusSearch() }
                    .keyboardShortcut("f", modifiers: .command)
                    .accessibilityHidden(true)
                    .frame(width: 0, height: 0)
                    .opacity(0)
            )
            // ⌘R — Refresh
            .background(
                Button("") { onRefresh() }
                    .keyboardShortcut("r", modifiers: .command)
                    .accessibilityHidden(true)
                    .frame(width: 0, height: 0)
                    .opacity(0)
            )
            // ⌘⇧S — Send for Signature
            .background(
                Button("") { onSendForSignature() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .accessibilityHidden(true)
                    .frame(width: 0, height: 0)
                    .opacity(0)
            )
    }
}

// MARK: - View extension

public extension View {
    /// Attaches §22 estimate keyboard shortcuts to the view.
    ///
    /// - Parameters:
    ///   - onNew: Fires on ⌘N. Typically presents the create sheet.
    ///   - onFocusSearch: Fires on ⌘F. Typically focuses the search field.
    ///   - onRefresh: Fires on ⌘R. Typically triggers a list refresh.
    ///   - onSendForSignature: Fires on ⌘⇧S. Typically presents the sign sheet.
    func estimateKeyboardShortcuts(
        onNew: @escaping () -> Void,
        onFocusSearch: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onSendForSignature: @escaping () -> Void
    ) -> some View {
        modifier(EstimateKeyboardShortcutsModifier(
            onNew: onNew,
            onFocusSearch: onFocusSearch,
            onRefresh: onRefresh,
            onSendForSignature: onSendForSignature
        ))
    }
}

// MARK: - EstimateKeyboardShortcutsConfig

/// Declarative record of all §22 keyboard shortcuts.
/// Use in UI tests and accessibility audits to enumerate expected bindings.
public struct EstimateKeyboardShortcutsConfig: Sendable {

    public struct ShortcutEntry: Sendable, Equatable {
        public let key: Character
        public let modifiers: EventModifiers
        public let description: String

        public init(key: Character, modifiers: EventModifiers, description: String) {
            self.key = key
            self.modifiers = modifiers
            self.description = description
        }
    }

    public static let all: [ShortcutEntry] = [
        ShortcutEntry(key: "n", modifiers: .command,             description: "New Estimate"),
        ShortcutEntry(key: "f", modifiers: .command,             description: "Focus Search"),
        ShortcutEntry(key: "r", modifiers: .command,             description: "Refresh"),
        ShortcutEntry(key: "s", modifiers: [.command, .shift],   description: "Send for Signature"),
    ]
}

#endif
