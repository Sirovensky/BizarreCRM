import SwiftUI

// §30 — Curve tokens
// Implements "Curve tokens: `standard` .easeInOut; `bouncy` spring(0.55, 0.7);
// `crisp` spring(0.4, 1.0); `gentle` spring(0.8, 0.5)" from ActionPlan §30
// line 4699.
//
// `MotionEasingSpec` already exposes `standard / decelerate / accelerate /
// emphasized` — this file adds the §30 "feel" curves (bouncy, crisp, gentle)
// that `MotionEasingSpec` deliberately doesn't model. Together they cover
// both the M3-flavoured ease curves AND the brand spring catalogue.
//
// APPEND-ONLY — do not rename or remove existing cases.

// MARK: - BrandCurve

/// Brand-defined curve catalogue. Each case maps to a SwiftUI `Animation`
/// at a duration the caller picks — the response/damping pair encoded in the
/// case name is the spring identity, not the playback length.
///
/// Usage:
/// ```swift
/// withAnimation(BrandCurve.bouncy.animation(duration: 0.30)) {
///     selectedTab = newTab
/// }
/// ```
public enum BrandCurve: String, Sendable, CaseIterable {

    /// `.easeInOut` — symmetric content swap.
    case standard

    /// Spring(response: 0.55, dampingFraction: 0.7) — playful overshoot.
    /// Use for "yes!" moments: payment success, lead conversion, achievement.
    case bouncy

    /// Spring(response: 0.4, dampingFraction: 1.0) — critical-damped snap.
    /// No overshoot, but still spring-feel. Use for confirmation chips,
    /// status pill swaps, anything where a wiggle would feel unprofessional.
    case crisp

    /// Spring(response: 0.8, dampingFraction: 0.5) — slow, soft, breathing.
    /// Use for ambient pulses (breath ring on idle CFD), onboarding lifts,
    /// background-art transitions.
    case gentle

    /// Returns a SwiftUI `Animation` for this curve at the supplied duration.
    /// For spring curves, `duration` maps to `response` so callers can still
    /// reach for the four named MotionDurationSpec steps when composing.
    public func animation(duration: Double) -> Animation {
        switch self {
        case .standard:
            return .easeInOut(duration: duration)
        case .bouncy:
            return .interactiveSpring(response: max(0.55, duration), dampingFraction: 0.70)
        case .crisp:
            return .interactiveSpring(response: max(0.40, duration), dampingFraction: 1.00)
        case .gentle:
            return .interactiveSpring(response: max(0.80, duration), dampingFraction: 0.50)
        }
    }

    /// Convenience using the curve's natural response time.
    public var animation: Animation {
        switch self {
        case .standard: return .easeInOut(duration: 0.30)
        case .bouncy:   return .interactiveSpring(response: 0.55, dampingFraction: 0.70)
        case .crisp:    return .interactiveSpring(response: 0.40, dampingFraction: 1.00)
        case .gentle:   return .interactiveSpring(response: 0.80, dampingFraction: 0.50)
        }
    }
}
