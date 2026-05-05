import SwiftUI

// MARK: - KeyboardShortcutBinder

/// `ViewModifier` that looks up a shortcut by catalog `id` and attaches a
/// `.keyboardShortcut` modifier that fires `onAction` when triggered.
///
/// If the `id` is not found in `KeyboardShortcutCatalog` the modifier is a
/// no-op so the view still compiles and works without the binding.
///
/// Example:
/// ```swift
/// Button("New Ticket") { createTicket() }
///     .modifier(KeyboardShortcutBinder(id: "new_ticket") { createTicket() })
/// ```
///
/// Convenience:
/// ```swift
/// Button("New Ticket") { createTicket() }
///     .registeredKeyboardShortcut(id: "new_ticket") { createTicket() }
/// ```
public struct KeyboardShortcutBinder: ViewModifier {
    public let id: String
    public let onAction: @Sendable () -> Void

    public init(id: String, onAction: @escaping @Sendable () -> Void) {
        self.id = id
        self.onAction = onAction
    }

    public func body(content: Content) -> some View {
        if let shortcut = KeyboardShortcutCatalog.shortcut(id: id) {
            content
                .background {
                    // Hidden button captures the key combination and fires
                    // `onAction`. The visible `content` is untouched.
                    Button {
                        onAction()
                    } label: {
                        EmptyView()
                    }
                    .keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
        } else {
            content
        }
    }
}

// MARK: - View convenience extension

public extension View {
    /// Attaches a keyboard shortcut from the central catalog to this view.
    ///
    /// - Parameters:
    ///   - id: The catalog entry `id` (e.g. `"new_ticket"`).
    ///   - onAction: Closure called when the shortcut is pressed.
    func registeredKeyboardShortcut(
        id: String,
        onAction: @escaping @Sendable () -> Void
    ) -> some View {
        modifier(KeyboardShortcutBinder(id: id, onAction: onAction))
    }
}
