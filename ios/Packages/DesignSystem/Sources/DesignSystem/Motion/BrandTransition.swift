import SwiftUI

// §67 — BrandTransition
// Named SwiftUI Transition factories for the app.
// APPEND-ONLY — do not rename or remove existing factories.

// MARK: - BrandTransition

/// Factory namespace for named SwiftUI `AnyTransition` values.
///
/// All transitions respect Reduce Motion via the `reduceMotion` parameter.
/// When `reduceMotion` is `true` they degrade to `.opacity` (a cross-fade)
/// which remains perceptible without spatial movement — matching Apple HIG.
///
/// Usage:
/// ```swift
/// @Environment(\.accessibilityReduceMotion) var reduceMotion
///
/// myView
///     .transition(BrandTransition.slideFromTrailing(reduceMotion: reduceMotion))
/// ```
public enum BrandTransition {

    // MARK: - Slide from trailing edge

    /// Content enters from the trailing edge and exits to the leading edge.
    /// Suitable for push-navigation and right-to-left step progressions.
    ///
    /// Reduce Motion fallback: `.opacity`.
    public static func slideFromTrailing(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion:  .move(edge: .trailing).combined(with: .opacity),
            removal:    .move(edge: .leading).combined(with: .opacity)
        )
    }

    // MARK: - Fade + scale

    /// Content fades in while scaling from 92 % → 100 %, fades out at 100 %.
    /// Suitable for popovers, tooltips, and contextual overlays.
    ///
    /// Reduce Motion fallback: `.opacity`.
    public static func fadeScale(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion:  .opacity.combined(with: .scale(scale: 0.92, anchor: .center)),
            removal:    .opacity
        )
    }

    // MARK: - Card flip

    /// Simulates a card flip using scale + opacity.
    /// Use for two-sided cards (e.g. front/back of a data card).
    ///
    /// Reduce Motion fallback: `.opacity`.
    public static func cardFlip(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        // SwiftUI's 2-D approximation: scale on the X axis via asymmetric scale.
        return .asymmetric(
            insertion:  .opacity.combined(with: .scale(scale: 0.01, anchor: .leading)),
            removal:    .opacity.combined(with: .scale(scale: 0.01, anchor: .trailing))
        )
    }

    // MARK: - Hero zoom

    /// Expands from a thumbnail source into a full-screen destination.
    /// Suitable for image / detail hero transitions.
    ///
    /// Reduce Motion fallback: `.opacity`.
    public static func heroZoom(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion:  .opacity.combined(with: .scale(scale: 0.75, anchor: .center)),
            removal:    .opacity.combined(with: .scale(scale: 1.15, anchor: .center))
        )
    }

    // MARK: - Opacity + transform (§29.8 perf-preferred)

    /// Opacity + transform (scale) only — never animates layout-affecting
    /// properties. Per §29.8 Animations: opacity + transform is preferred
    /// over layout changes because transforms are GPU-composited and don't
    /// invalidate sibling layout, while animated heights / widths force a
    /// layout pass on every frame which thrashes on long lists.
    ///
    /// Use this for any "appear / disappear" effect inside a parent that
    /// itself scrolls or whose siblings would otherwise re-flow.
    ///
    /// Reduce Motion fallback: `.opacity` (transform suppressed).
    public static func opacityTransform(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .opacity.combined(with: .scale(scale: 0.96, anchor: .center))
    }

    // MARK: - Page transition (§30 spring)

    /// Spring-driven page push: enters from trailing, exits to leading.
    ///
    /// Paired animation: `BrandMotion.pageTransition` (response 0.36, damping 0.82).
    /// Use with `.transition(BrandTransition.page(reduceMotion:))` inside a
    /// `NavigationStack` custom column or a `ZStack`-based paged view.
    ///
    /// Reduce Motion fallback: `.opacity`.
    public static func page(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion:  .move(edge: .trailing).combined(with: .opacity),
            removal:    .move(edge: .leading).combined(with: .opacity)
        )
    }
}
