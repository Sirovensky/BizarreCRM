import SwiftUI

// MARK: - SettingsKeyboardShortcuts

/// iPad keyboard shortcuts for the Settings 3-col shell.
///
/// Attach via `.settingsKeyboardShortcuts(...)` on `SettingsThreeColumnShell`.
/// Each command fires a closure so the shell can update its owned state without
/// the shortcut handler reaching into SwiftUI internals.
public struct SettingsKeyboardShortcutsModifier: ViewModifier {

    /// Called when ⌘, is pressed (open Settings — handled by the scene).
    var onOpenSettings: (() -> Void)?

    /// Called when ⌘F / ⌘⇧F is pressed (focus the search field).
    var onFocusSearch: (() -> Void)?

    /// Called when Escape is pressed while search is active (dismiss search).
    var onDismissSearch: (() -> Void)?

    /// Called when ⌘W is pressed (dismiss/pop settings sheet).
    var onClose: (() -> Void)?

    public func body(content: Content) -> some View {
        content
            // ⌘F — focus settings search field
            .keyboardShortcut("f", modifiers: .command)
            .simultaneousGesture(TapGesture().onEnded { _ in }) // required placeholder
            .background(
                KeyboardShortcutReceiver(
                    onOpenSettings: onOpenSettings,
                    onFocusSearch: onFocusSearch,
                    onDismissSearch: onDismissSearch,
                    onClose: onClose
                )
            )
    }
}

// MARK: - KeyboardShortcutReceiver (internal UIKit bridge)

/// Transparent overlay that registers `UIKeyCommand`s and routes them to Swift
/// closures. Avoids needing `@FocusState` tricks for commands that must work
/// even when no text field is focused.
private struct KeyboardShortcutReceiver: View {
    var onOpenSettings: (() -> Void)?
    var onFocusSearch: (() -> Void)?
    var onDismissSearch: (() -> Void)?
    var onClose: (() -> Void)?

    var body: some View {
        // Attach SwiftUI .commands via overlay buttons sized to 0 pt — they
        // still participate in the responder chain without appearing on screen.
        ZStack {
            // ⌘F
            Button("") { onFocusSearch?() }
                .keyboardShortcut("f", modifiers: .command)
                .accessibilityLabel("Search Settings")
                .accessibilityIdentifier("settings.shortcut.search")
                .frame(width: 0, height: 0)
                .opacity(0)

            // ⌘⇧F (alternate chord)
            Button("") { onFocusSearch?() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .accessibilityLabel("Search Settings")
                .accessibilityIdentifier("settings.shortcut.searchAlt")
                .frame(width: 0, height: 0)
                .opacity(0)

            // ⌘W — close / dismiss
            Button("") { onClose?() }
                .keyboardShortcut("w", modifiers: .command)
                .accessibilityLabel("Close Settings")
                .accessibilityIdentifier("settings.shortcut.close")
                .frame(width: 0, height: 0)
                .opacity(0)

            // ⌘, — open settings (usually handled by scene; provide here for
            //        completeness so it appears in the system ⌘-? overlay)
            Button("") { onOpenSettings?() }
                .keyboardShortcut(",", modifiers: .command)
                .accessibilityLabel("Open Settings")
                .accessibilityIdentifier("settings.shortcut.open")
                .frame(width: 0, height: 0)
                .opacity(0)

            // Escape — dismiss search (no modifier)
            Button("") { onDismissSearch?() }
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityLabel("Dismiss Search")
                .accessibilityIdentifier("settings.shortcut.escape")
                .frame(width: 0, height: 0)
                .opacity(0)
        }
    }
}

// MARK: - View extension

public extension View {
    /// Registers iPad keyboard shortcuts for the settings root.
    ///
    /// - Parameters:
    ///   - onFocusSearch: Called when ⌘F or ⌘⇧F is pressed.
    ///   - onDismissSearch: Called when Escape is pressed.
    ///   - onClose: Called when ⌘W is pressed.
    ///   - onOpenSettings: Called when ⌘, is pressed.
    func settingsKeyboardShortcuts(
        onFocusSearch: (() -> Void)? = nil,
        onDismissSearch: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil
    ) -> some View {
        modifier(SettingsKeyboardShortcutsModifier(
            onOpenSettings: onOpenSettings,
            onFocusSearch: onFocusSearch,
            onDismissSearch: onDismissSearch,
            onClose: onClose
        ))
    }
}

// MARK: - SettingsShortcutDescriptor (for discoverability)

/// Describes a single keyboard shortcut for display in the shortcuts help
/// overlay (press ⌘? on hardware keyboard to reveal).
public struct SettingsShortcutDescriptor: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let key: String
    public let modifiers: String

    public init(id: String, title: String, key: String, modifiers: String) {
        self.id = id
        self.title = title
        self.key = key
        self.modifiers = modifiers
    }

    /// All shortcuts registered by `settingsKeyboardShortcuts`.
    public static let all: [SettingsShortcutDescriptor] = [
        .init(id: "open",          title: "Open Settings",   key: ",",  modifiers: "⌘"),
        .init(id: "search",        title: "Search Settings", key: "F",  modifiers: "⌘"),
        .init(id: "searchAlt",     title: "Search Settings", key: "F",  modifiers: "⌘⇧"),
        .init(id: "close",         title: "Close Settings",  key: "W",  modifiers: "⌘"),
        .init(id: "dismissSearch", title: "Dismiss Search",  key: "Esc", modifiers: ""),
    ]
}
