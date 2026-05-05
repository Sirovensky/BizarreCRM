import SwiftUI

// §67 — MotionEasingSpec
// Named easing curves for the app's motion system.
// Maps to SwiftUI UnitCurve / Animation for composability.
// APPEND-ONLY — do not rename or remove existing cases.

// MARK: - MotionEasingSpec

/// Named easing curves following Material Design / HIG principles.
///
/// Build a concrete `Animation` by combining a curve with a duration:
/// ```swift
/// let anim = MotionEasingSpec.decelerate.animation(duration: MotionDurationSpec.medium.seconds)
/// ```
public enum MotionEasingSpec: CaseIterable, Sendable {

    /// General-purpose — symmetric acceleration and deceleration.
    /// Use for content that enters AND exits within the same gesture phase.
    case standard

    /// Elements entering the screen; starts fast, eases to rest.
    /// Analogous to `easeOut`.
    case decelerate

    /// Elements leaving the screen; starts slow, exits fast.
    /// Analogous to `easeIn`.
    case accelerate

    /// High-attention emphasis — fast departure, dramatic overshoot settle.
    /// Use for hero transitions and shared-element moves.
    case emphasized

    // MARK: - SwiftUI Animation factory

    /// Returns a SwiftUI `Animation` using this curve at the given duration.
    ///
    /// The `emphasized` case uses an `interactiveSpring` so the response
    /// duration is approximate; the spring settles naturally.
    public func animation(duration: Double) -> Animation {
        switch self {
        case .standard:
            return .easeInOut(duration: duration)
        case .decelerate:
            return .easeOut(duration: duration)
        case .accelerate:
            return .easeIn(duration: duration)
        case .emphasized:
            // Damping fraction tuned for a single visible overshoot.
            return .interactiveSpring(response: duration, dampingFraction: 0.72)
        }
    }

    // MARK: - UnitCurve representation

    /// Returns the closest SwiftUI `UnitCurve` for this easing case.
    /// Useful for `withAnimation` callers that prefer curve composition.
    public var unitCurve: UnitCurve {
        switch self {
        case .standard:
            return .easeInOut
        case .decelerate:
            return .easeOut
        case .accelerate:
            return .easeIn
        case .emphasized:
            // Custom cubic approximating emphasized easing (M3 spec).
            return .bezier(startControlPoint: UnitPoint(x: 0.05, y: 0.0),
                           endControlPoint:   UnitPoint(x: 0.133, y: 1.0))
        }
    }
}
