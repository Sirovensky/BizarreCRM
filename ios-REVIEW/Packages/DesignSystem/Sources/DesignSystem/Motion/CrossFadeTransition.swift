import SwiftUI

// §26.3 — CrossFadeTransition
// prefers-cross-fade-transitions: when Reduce Motion is enabled, every
// navigational or content-swap transition degrades to a plain opacity cross-fade
// instead of using spatial movement (slide, scale, zoom).
//
// This modifier wraps the SwiftUI `\.accessibilityReduceMotion` environment value
// and exposes a single call site for callers that want the HIG-recommended
// "still perceptible but non-spatial" fallback.

// MARK: - View modifier

/// Applies a cross-fade transition to this view when the system Reduce Motion
/// setting is enabled; otherwise applies the `fullTransition` you supply.
///
/// Gate every spatial navigation transition through this modifier to satisfy
/// §26.3 "prefers-cross-fade-transitions".
///
/// **Usage:**
/// ```swift
/// detailView
///     .prefersCrossFadeTransition(
///         full: BrandTransition.slideFromTrailing(reduceMotion: false)
///     )
/// ```
public struct CrossFadeTransitionModifier: ViewModifier {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The full spatial transition used when Reduce Motion is off.
    private let fullTransition: AnyTransition

    public init(full fullTransition: AnyTransition) {
        self.fullTransition = fullTransition
    }

    public func body(content: Content) -> some View {
        content
            .transition(reduceMotion ? .opacity : fullTransition)
    }
}

// MARK: - View extension

public extension View {

    /// Attaches a cross-fade transition when the system Reduce Motion setting
    /// is enabled, falling back to `full` when motion is allowed.
    ///
    /// - Parameter full: The spatial `AnyTransition` to use when Reduce Motion
    ///   is **off**. When Reduce Motion is **on**, `.opacity` (cross-fade) is
    ///   used instead — matching Apple's HIG recommendation for motion-sensitive
    ///   users.
    func prefersCrossFadeTransition(full: AnyTransition) -> some View {
        modifier(CrossFadeTransitionModifier(full: full))
    }

    /// Convenience overload: cross-fade replaces the default `slideFromTrailing`
    /// transition. Reads `reduceMotion` from the environment automatically.
    ///
    /// Equivalent to:
    /// ```swift
    /// .prefersCrossFadeTransition(
    ///     full: BrandTransition.slideFromTrailing(reduceMotion: false)
    /// )
    /// ```
    func prefersCrossFadeTransition() -> some View {
        prefersCrossFadeTransition(
            full: BrandTransition.slideFromTrailing(reduceMotion: false)
        )
    }
}
