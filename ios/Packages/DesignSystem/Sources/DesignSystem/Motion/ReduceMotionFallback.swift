import SwiftUI

// §67.3 — ReduceMotionFallback
// Gates animations behind the system Reduce Motion accessibility setting.

// MARK: - ReduceMotionFallback

/// Utility for applying Reduce Motion policy to animations.
///
/// Usage:
/// ```swift
/// @Environment(\.accessibilityReduceMotion) var reduceMotion
/// let anim = ReduceMotionFallback.animation(BrandMotion.modalSheet, reduced: reduceMotion)
/// withAnimation(anim) { ... }
/// ```
public enum ReduceMotionFallback: Sendable {

    // MARK: - Public API

    /// Returns `nil` (no animation) when `reduced` is `true`;
    /// otherwise returns `base`.
    ///
    /// Pass `nil` to `withAnimation(_:_:)` to produce an instant,
    /// frame-accurate update — the correct Reduce Motion behavior
    /// per Apple HIG (single-frame instead of spring).
    public static func animation(_ base: Animation, reduced: Bool) -> Animation? {
        reduced ? nil : base
    }

    /// Returns a fade (`.easeInOut(duration:0.15)`) when reduced,
    /// otherwise the full `base` animation.
    ///
    /// Use when a zero-duration snap is too jarring but springs are
    /// visually problematic (e.g. shared-element transitions).
    public static func fadeOrFull(_ base: Animation, reduced: Bool) -> Animation {
        reduced ? .easeInOut(duration: 0.15) : base
    }
}

// MARK: - View extensions

public extension View {

    /// Applies `withAnimation` using `BrandMotion` tokens, automatically
    /// falling back to `nil` (instant) when Reduce Motion is enabled.
    ///
    /// Example:
    /// ```swift
    /// .brandAnimation(BrandMotion.chipToggle, value: isSelected)
    /// ```
    func brandAnimation<V: Equatable>(
        _ animation: Animation,
        value: V,
        reduceMotion: Bool = false
    ) -> some View {
        self.animation(
            ReduceMotionFallback.animation(animation, reduced: reduceMotion),
            value: value
        )
    }
}
