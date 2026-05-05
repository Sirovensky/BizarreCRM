import SwiftUI

// §67 — MotionViewModifiers
// SwiftUI View extensions: .brandTransition(_:) and .brandAnimation(_:).
// These are the primary ergonomic entry points for §67 motion tokens in views.

// MARK: - BrandTransitionModifier

private struct BrandTransitionModifier: ViewModifier {
    let transition: AnyTransition

    func body(content: Content) -> some View {
        content.transition(transition)
    }
}

// MARK: - BrandAnimationModifier

private struct BrandAnimationModifier<V: Equatable>: ViewModifier {
    let preset: BrandAnimation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(preset.resolved(reduceMotion: reduceMotion), value: value)
    }
}

// MARK: - View extensions

public extension View {

    /// Attaches a `BrandTransition`-supplied `AnyTransition` to this view.
    ///
    /// Call the `BrandTransition` factory directly to build the transition:
    /// ```swift
    /// @Environment(\.accessibilityReduceMotion) var reduceMotion
    ///
    /// myCard
    ///     .brandTransition(BrandTransition.fadeScale(reduceMotion: reduceMotion))
    /// ```
    ///
    /// - Parameter transition: A pre-built `AnyTransition` from `BrandTransition`.
    func brandTransition(_ transition: AnyTransition) -> some View {
        modifier(BrandTransitionModifier(transition: transition))
    }

    /// Attaches a `BrandAnimation` preset to this view, automatically
    /// honouring `\.accessibilityReduceMotion` from the environment.
    ///
    /// Usage:
    /// ```swift
    /// myView
    ///     .brandAnimation(.smooth, value: isExpanded)
    /// ```
    ///
    /// - Parameters:
    ///   - preset: One of the named `BrandAnimation` cases.
    ///   - value: The `Equatable` value whose change triggers the animation.
    func brandAnimation<V: Equatable>(_ preset: BrandAnimation, value: V) -> some View {
        modifier(BrandAnimationModifier(preset: preset, value: value))
    }
}
