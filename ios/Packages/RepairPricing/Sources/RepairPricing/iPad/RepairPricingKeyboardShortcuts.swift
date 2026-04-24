import SwiftUI

// MARK: - §22 Repair Pricing Keyboard Shortcuts

/// `ViewModifier` that installs the three primary repair-pricing keyboard shortcuts:
///
///   ⌘N — New template
///   ⌘F — Find / focus search
///   ⌘R — Refresh / reload data
///
/// Apply via `.modifier(RepairPricingKeyboardShortcuts(...))` on the root
/// three-column view so the shortcuts are active whenever that view hierarchy
/// is on screen.
///
/// All closures are called on the main actor — the modifier is `@MainActor`-isolated.
public struct RepairPricingKeyboardShortcuts: ViewModifier {

    public let onNew: () -> Void
    public let onFind: () -> Void
    public let onRefresh: () -> Void

    public init(
        onNew: @escaping () -> Void,
        onFind: @escaping () -> Void,
        onRefresh: @escaping () -> Void
    ) {
        self.onNew = onNew
        self.onFind = onFind
        self.onRefresh = onRefresh
    }

    public func body(content: Content) -> some View {
        content
            .background(
                // Hidden buttons carry the keyboard shortcuts.
                // SwiftUI routes ⌘-key events to the active key window's
                // responder chain; placing the buttons in .background keeps
                // them out of the visible hierarchy while still registering.
                ShortcutButtons(onNew: onNew, onFind: onFind, onRefresh: onRefresh)
            )
    }
}

// MARK: - Shortcut buttons (hidden)

/// Three zero-size buttons that exist solely to register keyboard shortcuts.
private struct ShortcutButtons: View {
    let onNew: () -> Void
    let onFind: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        ZStack {
            // ⌘N — New template
            Button(action: onNew) { EmptyView() }
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityLabel("New template")
                .accessibilityIdentifier("shortcut.new")
                .frame(width: 0, height: 0)
                .hidden()

            // ⌘F — Find / focus search
            Button(action: onFind) { EmptyView() }
                .keyboardShortcut("f", modifiers: .command)
                .accessibilityLabel("Find")
                .accessibilityIdentifier("shortcut.find")
                .frame(width: 0, height: 0)
                .hidden()

            // ⌘R — Refresh
            Button(action: onRefresh) { EmptyView() }
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel("Refresh")
                .accessibilityIdentifier("shortcut.refresh")
                .frame(width: 0, height: 0)
                .hidden()
        }
        .accessibilityHidden(true)
    }
}

// MARK: - View convenience

public extension View {
    /// Attaches the three standard repair-pricing keyboard shortcuts.
    func repairPricingKeyboardShortcuts(
        onNew: @escaping () -> Void,
        onFind: @escaping () -> Void,
        onRefresh: @escaping () -> Void
    ) -> some View {
        modifier(RepairPricingKeyboardShortcuts(onNew: onNew, onFind: onFind, onRefresh: onRefresh))
    }
}
