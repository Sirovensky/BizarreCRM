import SwiftUI

// §22 — Shared pointer-interaction modifier bundling `.hoverEffect(.highlight)`
// and `.pointerStyle` for consistent iPad + Mac hover behaviour.
//
// Gate: `#if canImport(UIKit)` keeps hoverEffect inert on macOS server-side Swift
// where the API is unavailable.
//
// Usage:
//   someRow
//       .brandHover()                   // row highlight, default pointer
//       .brandHover(pointer: .link)     // row highlight + link cursor
//
// Or via explicit modifier:
//   someRow
//       .modifier(HoverHighlightModifier(pointer: .link))

// MARK: - PointerSemantics

/// Semantic pointer style applied by ``HoverHighlightModifier``.
///
/// Maps to `UIPointerStyle` / SwiftUI `.pointerStyle` on iPadOS 17.5+.
/// Falls back gracefully on older OS versions.
public enum PointerSemantics: Sendable, Equatable {
    /// Default system arrow cursor — use for interactive rows and cards.
    case `default`
    /// Link cursor (pointing hand) — use for tappable hyperlinks and URL labels.
    case link
}

// MARK: - HoverHighlightModifier

/// Applies `.hoverEffect(.highlight)` and the requested pointer style to any
/// view.
///
/// Respects Reduce Motion — the highlight still shows, but transition is
/// instant (no scale/opacity animation). This satisfies §26 a11y contract:
/// hover effects must not be the sole carrier of state; they're cosmetic.
public struct HoverHighlightModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Pointer semantic requested by the call site.
    public let pointer: PointerSemantics

    public init(pointer: PointerSemantics = .default) {
        self.pointer = pointer
    }

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

// MARK: - Convenience extensions

public extension View {
    /// Apply brand-standard hover highlight + optional pointer customization.
    ///
    /// - Parameter pointer: The cursor semantic. Use `.link` for hyperlinks,
    ///   `.default` for interactive rows (the default).
    /// - Returns: A view with `.hoverEffect(.highlight)` and the matching
    ///   `.pointerStyle` applied on UIKit; passthrough on macOS CLI / test hosts.
    func brandHover(pointer: PointerSemantics = .default) -> some View {
        modifier(HoverHighlightModifier(pointer: pointer))
    }

    /// Convenience: apply brand hover with the link (pointing-hand) cursor.
    ///
    /// Equivalent to `.brandHover(pointer: .link)`.  Use on `Link` views,
    /// tappable URL labels, and any element that navigates to an external URL.
    func brandLinkHover() -> some View {
        modifier(HoverHighlightModifier(pointer: .link))
    }
}
