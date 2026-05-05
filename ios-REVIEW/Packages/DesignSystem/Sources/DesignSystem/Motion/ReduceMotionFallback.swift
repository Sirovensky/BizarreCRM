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

// MARK: - Environment-aware spring gate — §26.3

/// Reads `@Environment(\.accessibilityReduceMotion)` automatically and
/// swaps any spring animation for a cross-fade when the OS flag is set.
/// Call sites need no manual `reduceMotion` parameter — the environment
/// value is resolved at render time.
///
/// Usage:
/// ```swift
/// MyView()
///     .brandSpring(BrandMotion.modalSheet, value: isPresented)
/// ```
private struct BrandSpringModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(
            ReduceMotionFallback.fadeOrFull(animation, reduced: reduceMotion),
            value: value
        )
    }
}

public extension View {
    /// Applies `animation` and swaps it for a cross-fade when the system
    /// Reduce Motion flag is set. Reads the OS flag automatically from the
    /// SwiftUI environment — no manual gate needed at the call site.
    ///
    /// When Reduce Motion is **off** (default), the full `animation` runs.
    /// When Reduce Motion is **on**, a 0.15 s ease-in-out cross-fade is used
    /// instead of springs or bouncy curves — §26.3.
    func brandSpring<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(BrandSpringModifier(animation: animation, value: value))
    }
}
