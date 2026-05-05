import SwiftUI

// §22 (iPad Pro M4) — ProMotion 120Hz display detection + animation boost.
//
// iPad Pro M4 (and iPhone 13 Pro and later) features a 120Hz ProMotion display.
// Animations tuned for 60fps look "slow" on ProMotion hardware; this helper
// detects 120Hz capability and exposes an `@Environment` key so views can
// select faster timing curves.
//
// MVP scope:
//  - Custom `EnvironmentKey` `\.isProMotion` (Bool).
//  - `ProMotionAnimationBoostModifier` that injects the key.
//  - `BrandMotion` already has timing tokens; ProMotion halves the "quick"
//    and "snappy" durations via a multiplier.

// MARK: - Environment key

private struct IsProMotionKey: EnvironmentKey {
    static let defaultValue: Bool = ProMotionDetector.isProMotion
}

public extension EnvironmentValues {
    /// `true` when the device reports a 120Hz+ ProMotion display.
    ///
    /// Inject via `.proMotionEnvironment()` on the root view, or read via
    /// `@Environment(\.isProMotion)` in any child view.
    var isProMotion: Bool {
        get { self[IsProMotionKey.self] }
        set { self[IsProMotionKey.self] = newValue }
    }
}

// MARK: - Detector

/// Detects ProMotion (120Hz) display capability.
///
/// Uses `CADisplayLink.preferredFramesPerSecond` or the iOS 15+
/// `UIScreen.main.maximumFramesPerSecond` API.
public struct ProMotionDetector: Sendable {
    private init() {}

    /// `true` when the main display supports ≥ 120Hz refresh.
    public static var isProMotion: Bool {
        #if canImport(UIKit)
        if #available(iOS 15, *) {
            return MainActor.assumeIsolated { UIScreen.main.maximumFramesPerSecond } >= 120
        } else {
            // Fallback: check CADisplayLink — not available at static init time,
            // so default to `false` (safe, not a crash path).
            return false
        }
        #else
        return false
        #endif
    }
}

// MARK: - Timing multiplier

/// Duration multiplier for ProMotion-aware animations.
///
/// On 120Hz displays the perceptual "weight" of an animation halves because
/// the hardware renders twice as many frames. Apply this multiplier to
/// `BrandMotion` timing tokens to keep animations feeling snappy on ProMotion
/// without looking rushed on 60Hz displays.
///
/// ```swift
/// @Environment(\.isProMotion) private var isProMotion
///
/// let duration = BrandMotion.quick * ProMotionAnimationBoost.multiplier(isProMotion)
/// ```
public struct ProMotionAnimationBoost: Sendable {
    private init() {}

    /// Returns `0.75` on ProMotion displays, `1.0` on 60Hz.
    ///
    /// Multiply against any `BrandMotion` duration token to get a
    /// ProMotion-adjusted value.
    public static func multiplier(_ isProMotion: Bool) -> Double {
        isProMotion ? 0.75 : 1.0
    }

    /// Convenience: multiply `duration` by the ProMotion factor.
    public static func adjusted(_ duration: Double, isProMotion: Bool) -> Double {
        duration * multiplier(isProMotion)
    }
}

// MARK: - View modifier

/// Injects `\.isProMotion` into the environment for all descendant views.
///
/// Apply once on the root view (e.g. `DashboardView` or `iPadSplitView`).
public struct ProMotionEnvironmentModifier: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .environment(\.isProMotion, ProMotionDetector.isProMotion)
    }
}

// MARK: - View extension

public extension View {
    /// Injects the `\.isProMotion` environment key into this view's subtree.
    func proMotionEnvironment() -> some View {
        self.modifier(ProMotionEnvironmentModifier())
    }
}
