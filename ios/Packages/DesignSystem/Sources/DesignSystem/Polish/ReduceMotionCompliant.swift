import SwiftUI

// MARK: - ReduceMotionCompliantModifier

/// Swaps between an animated view and a static alternative based on
/// `@Environment(\.accessibilityReduceMotion)`.
///
/// Use this whenever you want a single call site to handle both the
/// "full motion" and "no motion" variants of a view, rather than
/// sprinkling conditional checks throughout your view body.
///
/// **Usage:**
/// ```swift
/// // Provide both variants inline:
/// SomeAnimatedChart()
///     .reduceMotionCompliant {
///         StaticChartSnapshot()
///     }
///
/// // Or just suppress animation on the same view:
/// BouncingBadge()
///     .reduceMotionCompliant { StaticBadge() }
/// ```
public struct ReduceMotionCompliantModifier<StaticContent: View>: ViewModifier {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The static (non-animated) alternative shown when Reduce Motion is on.
    private let staticContent: () -> StaticContent

    public init(@ViewBuilder staticContent: @escaping () -> StaticContent) {
        self.staticContent = staticContent
    }

    public func body(content: Content) -> some View {
        if reduceMotion {
            staticContent()
        } else {
            content
        }
    }
}

// MARK: - View extension

public extension View {
    /// Replaces this view with `staticContent` when Reduce Motion is enabled.
    ///
    /// - Parameter staticContent: A `@ViewBuilder` that returns the
    ///   non-animated alternative. Called only when Reduce Motion is on.
    func reduceMotionCompliant<S: View>(
        @ViewBuilder staticContent: @escaping () -> S
    ) -> some View {
        modifier(ReduceMotionCompliantModifier(staticContent: staticContent))
    }
}
