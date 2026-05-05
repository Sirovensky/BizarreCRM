import Foundation
import SwiftUI

// MARK: - §30 Duration scale tokens
//
// ActionPlan §30 calls for a six-step named duration scale distinct from
// the four-step `MotionDurationSpec` (instant/short/medium/long) used by
// §67. The scale below mirrors §30 verbatim:
//
//   • instant  0ms   — state flip
//   • quick    150ms — selection / hover
//   • snappy   220ms — chip pop, toast
//   • smooth   350ms — nav push, sheet present
//   • gentle   500ms — celebratory
//   • slow     800ms — decorative, onboarding
//
// `MotionDurationSpec` is APPEND-ONLY per §67 conventions and not safe
// to renumber, so this file lives alongside it as a separate token set.
// Pair with `BrandCurve` for the (curve, duration) pair callers usually
// want, e.g.:
//
//     .animation(BrandDurationScale.snappy.animation(curve: .crisp), value: flag)

public enum BrandDurationScale: Double, CaseIterable, Sendable {

    /// 0 ms — instantaneous state flip; no perceptible animation.
    case instant = 0.000

    /// 150 ms — selection / hover feedback; just enough to be felt.
    case quick   = 0.150

    /// 220 ms — chip pop, toast in/out; brisk but legible.
    case snappy  = 0.220

    /// 350 ms — nav push, sheet present; perceptible polish.
    case smooth  = 0.350

    /// 500 ms — celebratory beats (success confirmation, tile flip).
    case gentle  = 0.500

    /// 800 ms — decorative / onboarding flourish; rarely on critical path.
    case slow    = 0.800

    // MARK: - Convenience

    /// Duration in seconds (same as rawValue, alias for readability).
    public var seconds: Double { rawValue }

    /// Duration as a `TimeInterval` (identical to `seconds`).
    public var timeInterval: TimeInterval { rawValue }

    /// `true` when this token is `> .snappy`. Per §30 Reduce-Motion rule,
    /// these durations should collapse to instant / opacity-only when
    /// the user has Reduce Motion enabled.
    public var requiresReduceMotionDowngrade: Bool {
        rawValue > BrandDurationScale.snappy.rawValue
    }

    // MARK: - SwiftUI bridges

    /// Build a SwiftUI `Animation` paired with a `BrandCurve`. Honours
    /// Reduce Motion by collapsing durations beyond `.snappy` to instant.
    public func animation(
        curve: BrandCurve = .standard,
        reduceMotion: Bool = false
    ) -> Animation {
        if reduceMotion && requiresReduceMotionDowngrade {
            return .easeInOut(duration: 0)
        }
        if rawValue == 0 {
            return .easeInOut(duration: 0)
        }
        return curve.animation(duration: rawValue)
    }
}
