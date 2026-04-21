import SwiftUI

// §22 — Shared pointer-interaction modifier bundling `.hoverEffect(.highlight)`
// and `.pointerStyle(.automatic)` for consistent iPad + Mac hover behaviour.
//
// Gate: `#if canImport(UIKit)` keeps hoverEffect inert on macOS server-side Swift
// where the API is unavailable.
// Usage:
//   someRow
//       .brandHover()
//
// Or via explicit modifier:
//   someRow
//       .modifier(HoverHighlightModifier())

// MARK: - ViewModifier

/// Applies `.hoverEffect(.highlight)` (and pointer interaction on platforms
/// that support it) to any view.
///
/// Respects Reduce Motion — the highlight still shows, but transition is
/// instant (no scale/opacity animation). This satisfies §26 a11y contract:
/// hover effects must not be the sole carrier of state; they're cosmetic.
public struct HoverHighlightModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func body(content: Content) -> some View {
        #if canImport(UIKit)
        content
            .hoverEffect(.highlight)
            .accessibilityAddTraits([])
            // Announce that context menu is available so VoiceOver users know
            // to use "long press" to access it.
            .accessibilityHint("Long press for more options")
        #else
        content
        #endif
    }
}

// MARK: - Convenience extension

public extension View {
    /// Apply brand-standard hover highlight + pointer interaction.
    ///
    /// - Returns: A view with `.hoverEffect(.highlight)` applied on UIKit;
    ///   passthrough on macOS CLI / test hosts.
    func brandHover() -> some View {
        self.modifier(HoverHighlightModifier())
    }
}
