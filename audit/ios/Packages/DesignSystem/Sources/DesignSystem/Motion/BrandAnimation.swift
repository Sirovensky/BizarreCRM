import SwiftUI

// §67 — BrandAnimation
// Named Animation presets with built-in Reduce Motion fallbacks.
// APPEND-ONLY — do not rename or remove existing presets.

// MARK: - BrandAnimation

/// Named `Animation` presets for the app.
///
/// Every preset has a Reduce Motion fallback:
/// - `.none` returns `nil` to `withAnimation(_:)`, producing an instant
///   frame-accurate update (Apple HIG recommendation).
///
/// Usage:
/// ```swift
/// @Environment(\.accessibilityReduceMotion) var reduceMotion
/// let anim = BrandAnimation.snappy.resolved(reduceMotion: reduceMotion)
/// withAnimation(anim) { isExpanded = true }
/// ```
public enum BrandAnimation: CaseIterable, Sendable {

    /// Fast, decisive — chip pop, icon swap, badge change.
    /// Duration: 200 ms, decelerate curve.
    case snappy

    /// Confident, polished — navigation push, sheet present.
    /// Duration: 320 ms, interactive spring.
    case smooth

    /// Gentle, unhurried — success celebrate, onboarding reveal.
    /// Duration: 480 ms, ease-in-out.
    case soft

    // MARK: - Full animation (ignores Reduce Motion)

    /// The full animation regardless of accessibility settings.
    /// Prefer `resolved(reduceMotion:)` in production views.
    public var animation: Animation {
        switch self {
        case .snappy:
            return MotionEasingSpec.decelerate.animation(
                duration: MotionDurationSpec.short.seconds
            )
        case .smooth:
            return .interactiveSpring(
                response: MotionDurationSpec.medium.seconds,
                dampingFraction: 0.86
            )
        case .soft:
            return MotionEasingSpec.standard.animation(
                duration: MotionDurationSpec.long.seconds
            )
        }
    }

    // MARK: - Reduce Motion aware

    /// Returns `nil` when Reduce Motion is enabled (instant update),
    /// or the full animation otherwise.
    ///
    /// - Parameter reduceMotion: Value of `\.accessibilityReduceMotion`.
    public func resolved(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}
