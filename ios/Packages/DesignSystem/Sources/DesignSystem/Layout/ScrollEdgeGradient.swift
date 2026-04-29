import SwiftUI

// MARK: - ScrollEdgeGradient (§91.16 scroll-edge gradient)
//
// A fade-out overlay anchored to the bottom (or top, or both edges) of a
// scroll container to signal that more content is available below / above.
//
// The gradient fades from the surrounding surface color to transparent so it
// blends into any background.  Reduce-Transparency is respected: when the
// system setting is on the fade height shrinks to 8 pt (still indicates a
// boundary without heavy layering).
//
// Usage:
//   ScrollView {
//       content
//   }
//   .scrollEdgeGradient()                          // bottom fade, 48 pt
//   .scrollEdgeGradient(height: 64, edge: .top)    // top fade
//   .scrollEdgeGradient(height: 48, edge: .bottom, color: .bizarreSurfaceBase)

// MARK: - Edge enum

/// Which edge of the scroll container receives the gradient overlay.
public enum ScrollEdge {
    case top
    case bottom
    case both
}

// MARK: - ScrollEdgeGradientModifier

private struct ScrollEdgeGradientModifier: ViewModifier {

    let height: CGFloat
    let edge: ScrollEdge
    let color: Color

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        // When Reduce Transparency is on, shrink the fade so it does not
        // create a thick opaque band over scroll content.
        let effectiveHeight = reduceTransparency ? min(8, height) : height

        content
            .overlay(alignment: .bottom) {
                if edge == .bottom || edge == .both {
                    bottomGradient(height: effectiveHeight)
                }
            }
            .overlay(alignment: .top) {
                if edge == .top || edge == .both {
                    topGradient(height: effectiveHeight)
                }
            }
    }

    private func bottomGradient(height: CGFloat) -> some View {
        LinearGradient(
            stops: [
                .init(color: color.opacity(0), location: 0),
                .init(color: color.opacity(0.85), location: 0.6),
                .init(color: color, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func topGradient(height: CGFloat) -> some View {
        LinearGradient(
            stops: [
                .init(color: color, location: 0),
                .init(color: color.opacity(0.85), location: 0.4),
                .init(color: color.opacity(0), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - View extension

public extension View {
    /// Overlays a fade gradient at the scroll edge to indicate more content.
    ///
    /// - Parameters:
    ///   - height: Gradient band height in points. Default 48 pt.
    ///   - edge: Which edge(s) to fade. Default `.bottom`.
    ///   - color: The opaque color to fade toward. Default `bizarreSurfaceBase`.
    ///     Pass the surrounding background color when it differs.
    ///
    /// ```swift
    /// ScrollView { longContent }
    ///     .scrollEdgeGradient()
    ///
    /// // Custom height and color:
    /// ScrollView { content }
    ///     .scrollEdgeGradient(height: 64, color: .bizarreSurface1)
    /// ```
    func scrollEdgeGradient(
        height: CGFloat = 48,
        edge: ScrollEdge = .bottom,
        color: Color = Color("bizarreSurfaceBase", bundle: DesignSystemBundle.bundle)
    ) -> some View {
        self.modifier(
            ScrollEdgeGradientModifier(
                height: max(0, height),
                edge: edge,
                color: color
            )
        )
    }
}
