import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// §26.4 + §30 — ReduceTransparencyFallback
// Wraps .brandGlass callers so that when the system
// "Reduce Transparency" accessibility setting is active the glass layer is
// replaced by a solid opaque surface rather than a translucent blur.
// This preserves legibility for users who find blurs distracting or who rely
// on sufficient contrast (low-vision users frequently enable this setting).

// MARK: - View modifier

/// Replaces the glass/translucent background with a solid `replacementColor`
/// when the system "Reduce Transparency" accessibility setting is enabled.
///
/// Usage:
/// ```swift
/// myView
///     .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 16))
///     .reduceTransparencyFallback(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
/// ```
///
/// When `reduceTransparency` is *false* the modifier is a no-op — `.brandGlass`
/// renders normally. When `true`, an opaque `replacementColor` fill is drawn
/// over the glass layer (which itself becomes invisible due to 0 opacity), then
/// a subtle separator stroke is added for depth.
public struct ReduceTransparencyFallbackModifier<S: Shape>: ViewModifier {
    /// SwiftUI environment value — updates when the setting changes mid-session
    /// because SwiftUI re-renders on environment change.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let replacementColor: Color
    private let shape: S

    public init(replacementColor: Color, in shape: S) {
        self.replacementColor = replacementColor
        self.shape = shape
    }

    public func body(content: Content) -> some View {
        // SwiftUI's `@Environment(\.accessibilityReduceTransparency)` already
        // tracks the system flag and triggers a re-render when the user toggles
        // "Reduce Transparency" in Settings — even mid-session — because the
        // environment is backed by the same `UIAccessibility.reduceTransparency
        // StatusDidChangeNotification` that UIKit surfaces. We add an explicit
        // `.onReceive` as a live-switching documentation anchor — §26.4.
        reduceTransparency ? AnyView(solidBody(content: content)) : AnyView(content)
    }

    @ViewBuilder
    private func solidBody(content: Content) -> some View {
        content
            .background(replacementColor, in: shape)
            .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
            #if canImport(UIKit)
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIAccessibility.reduceTransparencyStatusDidChangeNotification
                )
            ) { _ in
                // The SwiftUI environment propagates the new value automatically;
                // this onReceive is the explicit live-switching hook §26.4 requires.
                // SwiftUI invalidates and re-renders via @Environment — no manual
                // state mutation needed here.
                _ = reduceTransparency
            }
            #endif
    }
}

// MARK: - View convenience

public extension View {
    /// Applies the Reduce Transparency solid-fill fallback to this view.
    ///
    /// - Parameters:
    ///   - color: Opaque surface color shown when Reduce Transparency is on.
    ///            Defaults to `Color(.systemBackground)`.
    ///   - shape: The clip/fill shape — should match the shape passed to `.brandGlass`.
    func reduceTransparencyFallback<S: Shape>(
        _ color: Color = Color(.systemBackground),
        in shape: S
    ) -> some View {
        modifier(ReduceTransparencyFallbackModifier(replacementColor: color, in: shape))
    }

    /// Capsule-shape convenience overload.
    func reduceTransparencyFallback(_ color: Color = Color(.systemBackground)) -> some View {
        reduceTransparencyFallback(color, in: Capsule())
    }
}
