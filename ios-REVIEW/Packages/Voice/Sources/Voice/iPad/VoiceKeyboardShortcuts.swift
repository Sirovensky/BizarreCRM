import SwiftUI

/// §22 — Keyboard shortcut constants for the Voice screens on iPad / Mac.
///
/// Defined shortcuts:
///   - **⌘F** — Focus the search field (triggers `.searchable` activation).
///   - **⌘C** — Callback: dials the currently-selected call or voicemail.
///   - **Space** — Play / pause the inline voicemail player.
///
/// Shortcut descriptors are exposed as static constants so tests can verify
/// the expected key + modifier combination without a UIKit / UIApplication host.
public enum VoiceShortcut {

    // MARK: - Descriptors

    /// ⌘F — focus / open the search field.
    public static let search    = KeyEquivalent("f")
    /// ⌘C — initiate a callback call.
    public static let callback  = KeyEquivalent("c")
    /// Space — toggle play / pause.
    public static let playPause = KeyEquivalent(" ")

    /// Modifier for ⌘ shortcuts (search, callback).
    public static let commandModifiers: EventModifiers = .command
    /// No modifier needed for Space.
    public static let noModifiers: EventModifiers = []
}

#if canImport(UIKit)

// MARK: - View modifiers

public extension View {

    /// Attaches ⌘F to trigger `action` — typically focuses a `@FocusState`
    /// variable bound to a `.searchable` field.
    ///
    /// Only visible / active on iPad / Mac; harmless on iPhone.
    func voiceSearchShortcut(action: @escaping () -> Void) -> some View {
        modifier(VoiceSearchShortcutModifier(action: action))
    }

    /// Attaches ⌘C to trigger `action` — typically places a callback call
    /// to the currently-selected entry's phone number.
    func voiceCallbackShortcut(action: @escaping () -> Void) -> some View {
        modifier(VoiceCallbackShortcutModifier(action: action))
    }

    /// Attaches Space bar to toggle play/pause.
    ///
    /// Use on the parent container of `VoicemailInlinePlayer` if you want
    /// to intercept Space before it reaches the player itself.
    func voicePlayPauseShortcut(action: @escaping () -> Void) -> some View {
        modifier(VoicePlayPauseShortcutModifier(action: action))
    }
}

// MARK: - Modifier implementations

struct VoiceSearchShortcutModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .keyboardShortcut(
                VoiceShortcut.search,
                modifiers: VoiceShortcut.commandModifiers
            )
            // SwiftUI's .keyboardShortcut only attaches to Button or similar
            // interactive views. Wrap with an invisible button overlay so the
            // shortcut fires even when the content is a non-interactive container.
            .background(
                Button("") { action() }
                    .keyboardShortcut(
                        VoiceShortcut.search,
                        modifiers: VoiceShortcut.commandModifiers
                    )
                    .opacity(0)
                    .accessibilityHidden(true)
            )
    }
}

struct VoiceCallbackShortcutModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .background(
                Button("") { action() }
                    .keyboardShortcut(
                        VoiceShortcut.callback,
                        modifiers: VoiceShortcut.commandModifiers
                    )
                    .opacity(0)
                    .accessibilityHidden(true)
            )
    }
}

struct VoicePlayPauseShortcutModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .background(
                Button("") { action() }
                    .keyboardShortcut(
                        VoiceShortcut.playPause,
                        modifiers: VoiceShortcut.noModifiers
                    )
                    .opacity(0)
                    .accessibilityHidden(true)
            )
    }
}
#endif
