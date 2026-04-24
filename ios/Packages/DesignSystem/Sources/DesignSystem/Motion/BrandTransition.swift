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
}
