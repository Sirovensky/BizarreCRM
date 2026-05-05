import Foundation

// §67 — MotionDurationSpec
// Canonical named durations for the app's motion system.
// All durations are in seconds (Double) to match SwiftUI's Animation APIs.
// APPEND-ONLY — do not rename or remove existing cases.

// MARK: - MotionDurationSpec

/// Enumerated duration steps for §67 named transitions and animations.
///
/// Usage:
/// ```swift
/// .animation(.easeOut(duration: MotionDurationSpec.short.seconds), value: flag)
/// ```
public enum MotionDurationSpec: Double, CaseIterable, Sendable {

    /// 80 ms — icon swap, state-bit toggle; imperceptible but registers.
    case instant = 0.080

    /// 200 ms — chip, toast in/out, tab switch; quick but legible.
    case short   = 0.200

    /// 320 ms — sheet present, push navigation; perceptible polish.
    case medium  = 0.320

    /// 480 ms — shared-element / hero; deliberate, celebratory.
    case long    = 0.480

    // MARK: - Convenience

    /// Duration in seconds (same as rawValue, alias for readability).
    public var seconds: Double { rawValue }

    /// Duration as a `TimeInterval` (identical to `seconds`).
    public var timeInterval: TimeInterval { rawValue }
}
