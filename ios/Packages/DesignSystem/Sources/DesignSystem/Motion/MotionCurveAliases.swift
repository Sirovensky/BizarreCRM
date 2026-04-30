import SwiftUI

// §80 Tokens — motion curve aliases
//
// Maps BrandCurve / MotionEasingSpec combinations to canonical semantic names
// so call-sites express intent ("entering the screen") rather than mechanics
// ("easeOut 0.28s"). APPEND-ONLY — do not rename or remove existing tokens.
//
// Cross-refs:
//   BrandCurve.swift      — four feel-curve primitives (standard, bouncy, crisp, gentle)
//   MotionEasingSpec.swift — M3-flavoured named easing (standard, decelerate, accelerate, emphasized)
//   MotionDurationSpec.swift — named durations (instant, short, medium, long)
//   MotionCatalog.swift   — §67 raw catalog entries (chipToggle, fabAppear, …)
//
// Usage:
//   .animation(MotionCurveAlias.enter, value: isVisible)
//   .animation(MotionCurveAlias.exit,  value: isDismissed)

// MARK: - MotionCurveAlias

/// Semantic curve aliases that compose BrandCurve + MotionDurationSpec.
///
/// Each alias expresses a UI intent and hides the curve / duration selection.
/// Prefer these over raw BrandCurve or MotionEasingSpec at view call-sites.
public enum MotionCurveAlias {

    // MARK: Screen / navigation transitions

    /// Element entering the visible area — easeOut 200ms.
    /// Use for list rows, chips, and cards that appear after data loads.
    public static let enter: Animation =
        MotionEasingSpec.decelerate.animation(duration: MotionDurationSpec.short.seconds)

    /// Element leaving the visible area — easeIn 160ms.
    /// Slightly faster than enter so departures feel crisp rather than lingering.
    public static let exit: Animation =
        MotionEasingSpec.accelerate.animation(duration: 0.160)

    /// Full-page push / pop — standard spring 320ms.
    public static let pageEnter: Animation =
        MotionEasingSpec.standard.animation(duration: MotionDurationSpec.medium.seconds)

    /// Shared-element hero move — emphasized spring 480ms.
    /// Use for ticket-detail open from a row thumbnail.
    public static let heroTransition: Animation =
        MotionEasingSpec.emphasized.animation(duration: MotionDurationSpec.long.seconds)

    // MARK: Interactive / feedback

    /// Successful confirmation — bouncy spring 320ms.
    /// Use on payment success, ticket creation, achievement unlocks.
    public static let celebrate: Animation =
        BrandCurve.bouncy.animation(duration: MotionDurationSpec.medium.seconds)

    /// High-precision state change — critically-damped 160ms.
    /// Use for status pill swaps, toggle confirmations, form-field validation.
    public static let confirm: Animation =
        BrandCurve.crisp.animation(duration: 0.160)

    /// Ambient pulse / breathing — gentle spring 800ms.
    /// Use for idle CFD rings, onboarding art, background decorations.
    public static let ambient: Animation =
        BrandCurve.gentle.animation(duration: 0.800)

    /// Standard interactive feedback — easeInOut 200ms.
    /// Fallback alias for anything that doesn't fit a more specific name.
    public static let standard: Animation =
        BrandCurve.standard.animation(duration: MotionDurationSpec.short.seconds)

    // MARK: Disclosure / expand-collapse

    /// Disclosure chevron or accordion expand — crisp spring 200ms.
    public static let expand: Animation =
        BrandCurve.crisp.animation(duration: MotionDurationSpec.short.seconds)

    /// Disclosure chevron or accordion collapse — easeIn 160ms.
    public static let collapse: Animation =
        MotionEasingSpec.accelerate.animation(duration: 0.160)

    // MARK: Reduce Motion variants

    /// Returns the canonical `enter` animation, or a 150ms fade when
    /// `accessibilityReduceMotion` is active.
    public static func enter(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : enter
    }

    /// Returns the canonical `celebrate` animation, or a 150ms fade when
    /// `accessibilityReduceMotion` is active.
    public static func celebrate(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : celebrate
    }

    /// Returns the canonical `heroTransition` animation, or nil (instant)
    /// when `accessibilityReduceMotion` is active.
    public static func heroTransition(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : heroTransition
    }
}

// MARK: - View helpers

public extension View {

    /// Applies `MotionCurveAlias.enter` (or its reduce-motion variant) on the
    /// provided value change. Reads `accessibilityReduceMotion` from environment.
    func enterAnimation<V: Equatable>(value: V) -> some View {
        modifier(MotionCurveAliasModifier(aliasKind: .enter, value: value))
    }

    /// Applies `MotionCurveAlias.celebrate` (or its reduce-motion variant) on
    /// the provided value change.
    func celebrateAnimation<V: Equatable>(value: V) -> some View {
        modifier(MotionCurveAliasModifier(aliasKind: .celebrate, value: value))
    }
}

// MARK: - Internal modifier

private enum MotionCurveAliasKind { case enter, celebrate }

private struct MotionCurveAliasModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let aliasKind: MotionCurveAliasKind
    let value: V

    func body(content: Content) -> some View {
        let anim: Animation? = {
            switch aliasKind {
            case .enter:     return MotionCurveAlias.enter(reduceMotion: reduceMotion)
            case .celebrate: return MotionCurveAlias.celebrate(reduceMotion: reduceMotion)
            }
        }()
        content.animation(anim, value: value)
    }
}
