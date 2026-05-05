import Foundation
#if canImport(CoreHaptics)
import CoreHaptics
#endif

// §66 — HapticPatternLibrary
// Named AHAP / CHHapticPattern factories for all catalog patterns.
// Returns non-nil patterns on any device; callers guard haptic capability separately.

// MARK: - HapticPatternDescriptor

/// A value that can produce a `CHHapticPattern` on supporting hardware.
///
/// On non-CoreHaptics platforms (macOS, Simulator without Taptic simulation)
/// `makePattern()` returns `nil`; callers fall through to UIKit feedback.
public struct HapticPatternDescriptor: @unchecked Sendable, Equatable {

    // MARK: Stored state

    /// Debug-friendly name, also used in equality.
    public let name: String

    /// Underlying AHAP dictionary representation.
    /// `nil` on platforms where CoreHaptics is unavailable.
    public var ahapDictionary: [CHHapticPattern.Key: Any]? {
        #if canImport(CoreHaptics)
        return _ahapDictionary
        #else
        return nil
        #endif
    }

    #if canImport(CoreHaptics)
    private let _ahapDictionary: [CHHapticPattern.Key: Any]
    #endif

    // MARK: Equatable

    public static func == (lhs: HapticPatternDescriptor, rhs: HapticPatternDescriptor) -> Bool {
        lhs.name == rhs.name
    }

    // MARK: Init

    #if canImport(CoreHaptics)
    init(name: String, ahapDictionary: [CHHapticPattern.Key: Any]) {
        self.name = name
        self._ahapDictionary = ahapDictionary
    }
    #else
    init(name: String) {
        self.name = name
    }
    #endif

    // MARK: Pattern materialisation

    /// Attempts to build and return the `CHHapticPattern`.
    /// Returns `nil` on non-CoreHaptics platforms or if the AHAP data is malformed.
    public func makePattern() -> CHHapticPattern? {
        #if canImport(CoreHaptics)
        return try? CHHapticPattern(dictionary: _ahapDictionary)
        #else
        return nil
        #endif
    }
}

// MARK: - HapticPatternLibrary

/// Named factory methods for every app-level haptic pattern.
///
/// All methods return a `HapticPatternDescriptor` — a lightweight value type
/// that defers CoreHaptics object creation until `makePattern()` is called.
/// This keeps the factory testable without a running CHHapticEngine.
///
/// Design decisions per §66:
/// - Patterns are composed from primitive building blocks (transient taps,
///   continuous pulses, parameter curves) to match Apple HIG feedback categories.
/// - Intensities and sharpness values follow the brand tactile grammar:
///   success = gentle, error = sharp, notifications = confident but calm.
public enum HapticPatternLibrary: Sendable {

    // MARK: - Semantic patterns

    /// Short ascending triple-tap — confirms a positive completion.
    public static var success: HapticPatternDescriptor {
        crescendo(name: "success", intensities: [0.3, 0.5, 0.7], sharpness: 0.7, interval: 0.07)
    }

    /// Two medium taps with slight sharpness — draws attention without alarm.
    public static var warning: HapticPatternDescriptor {
        twoTap(name: "warning", intensity: 0.65, sharpness: 0.75, interval: 0.09)
    }

    /// Two sharp heavy taps — unmistakably communicates failure.
    public static var error: HapticPatternDescriptor {
        twoTap(name: "error", intensity: 0.9, sharpness: 0.95, interval: 0.08)
    }

    // MARK: - Commerce / POS patterns

    /// Three-tap crescendo (0.2 → 0.45 → 0.8) — celebrates a completed sale.
    public static var saleComplete: HapticPatternDescriptor {
        crescendo(name: "saleComplete", intensities: [0.2, 0.45, 0.8], sharpness: 0.65, interval: 0.06)
    }

    /// Single crisp tap — acknowledges a card/NFC presentation.
    public static var cardTap: HapticPatternDescriptor {
        singleTap(name: "cardTap", intensity: 0.5, sharpness: 0.9)
    }

    // MARK: - Device / peripheral patterns

    /// Ramp 0.3 → 0.7 over 120 ms — simulates device waking up.
    public static var deviceConnected: HapticPatternDescriptor {
        ramp(name: "deviceConnected", startIntensity: 0.3, endIntensity: 0.7, duration: 0.12)
    }

    /// Single gentle click — confirms a barcode was read.
    public static var barcodeScanned: HapticPatternDescriptor {
        singleTap(name: "barcodeScanned", intensity: 0.4, sharpness: 0.85)
    }

    // MARK: - Communication / UI patterns

    /// Medium single tap — informs of an incoming message or alert.
    public static var notification: HapticPatternDescriptor {
        singleTap(name: "notification", intensity: 0.6, sharpness: 0.6)
    }

    // MARK: - §66.2 Named catalog patterns

    /// 3-tap crescendo (0.1, 0.2, 0.4 intensity, 40ms apart) + chime association.
    /// Use for sale-complete confirmation (§66 table).
    public static var saleSuccess: HapticPatternDescriptor {
        crescendo(name: "saleSuccess", intensities: [0.1, 0.2, 0.4], sharpness: 0.65, interval: 0.04)
    }

    /// Two sharp heavy taps (0.9, 0.9, 80ms apart) — card declined.
    public static var cardDecline: HapticPatternDescriptor {
        twoTap(name: "cardDecline", intensity: 0.9, sharpness: 0.95, interval: 0.08)
    }

    /// Single medium thump — cash drawer open.
    public static var drawerOpen: HapticPatternDescriptor {
        singleTap(name: "drawerOpen", intensity: 0.8, sharpness: 0.3)
    }

    /// Single gentle click — barcode scan matched.
    public static var scanMatch: HapticPatternDescriptor {
        singleTap(name: "scanMatch", intensity: 0.4, sharpness: 0.85)
    }

    /// Double sharp taps — barcode scan unmatched (warning).
    public static var scanUnmatched: HapticPatternDescriptor {
        twoTap(name: "scanUnmatched", intensity: 0.75, sharpness: 0.9, interval: 0.07)
    }

    /// Ramp 0.2 → 0.6 over 150ms — status advancing forward.
    public static var statusAdvance: HapticPatternDescriptor {
        ramp(name: "statusAdvance", startIntensity: 0.2, endIntensity: 0.6, duration: 0.15)
    }

    /// Reverse ramp 0.6 → 0.2 over 150ms — undo action.
    public static var undo: HapticPatternDescriptor {
        ramp(name: "undo", startIntensity: 0.6, endIntensity: 0.2, duration: 0.15)
    }

    /// Triple subtle, low intensity — signature committed.
    public static var signatureComplete: HapticPatternDescriptor {
        crescendo(name: "signatureComplete", intensities: [0.2, 0.2, 0.2], sharpness: 0.4, interval: 0.06)
    }

    // MARK: - §16.25 / §4 Repair / Pickup patterns

    /// Four-tap ascending chime pattern (0.2 → 0.35 → 0.55 → 0.8) —
    /// played when a ticket transitions to "Ready for Pickup" so the
    /// cashier / tech gets a distinct tactile confirmation distinct from
    /// the generic sale-success crescendo.
    public static var pickupConfirm: HapticPatternDescriptor {
        crescendo(
            name: "pickupConfirm",
            intensities: [0.2, 0.35, 0.55, 0.8],
            sharpness: 0.55,
            interval: 0.07
        )
    }

    // MARK: - Private builders

    private static func singleTap(
        name: String,
        intensity: Float,
        sharpness: Float
    ) -> HapticPatternDescriptor {
        #if canImport(CoreHaptics)
        let dict: [CHHapticPattern.Key: Any] = [
            .pattern: [
                [
                    CHHapticPattern.Key.event: [
                        CHHapticPattern.Key.eventType: CHHapticEvent.EventType.hapticTransient.rawValue,
                        CHHapticPattern.Key.time: 0.0,
                        CHHapticPattern.Key.eventParameters: [
                            [CHHapticPattern.Key.parameterID: CHHapticEvent.ParameterID.hapticIntensity.rawValue,
                             CHHapticPattern.Key.parameterValue: intensity],
                            [CHHapticPattern.Key.parameterID: CHHapticEvent.ParameterID.hapticSharpness.rawValue,
                             CHHapticPattern.Key.parameterValue: sharpness]
                        ]
                    ]
                ]
            ]
        ]
        return HapticPatternDescriptor(name: name, ahapDictionary: dict)
        #else
        return HapticPatternDescriptor(name: name)
        #endif
    }

    private static func twoTap(
        name: String,
        intensity: Float,
        sharpness: Float,
        interval: TimeInterval
    ) -> HapticPatternDescriptor {
        #if canImport(CoreHaptics)
        let dict: [CHHapticPattern.Key: Any] = [
            .pattern: [
                [
                    CHHapticPattern.Key.event: [
                        CHHapticPattern.Key.eventType: CHHapticEvent.EventType.hapticTransient.rawValue,
                        CHHapticPattern.Key.time: 0.0,
                        CHHapticPattern.Key.eventParameters: [
                            [CHHapticPattern.Key.parameterID: CHHapticEvent.ParameterID.hapticIntensity.rawValue,
                             CHHapticPattern.Key.parameterValue: intensity],
                            [CHHapticPattern.Key.parameterID: CHHapticEvent.ParameterID.hapticSharpness.rawValue,
                             CHHapticPattern.Key.parameterValue: sharpness]
                        ]
                    ]
                ],
                [
                    CHHapticPattern.Key.event: [
                        CHHapticPattern.Key.eventType: CHHapticEvent.EventType.hapticTransient.rawValue,
                        CHHapticPattern.Key.time: interval,
                        CHHapticPattern.Key.eventParameters: [
                            [CHHapticPattern.Key.parameterID: CHHapticEvent.ParameterID.hapticIntensity.rawValue,
                             CHHapticPattern.Key.parameterValue: intensity],
                            [CHHapticPattern.Key.parameterID: CHHapticEvent.ParameterID.hapticSharpness.rawValue,
                             CHHapticPattern.Key.parameterValue: sharpness]
                        ]
                    ]
                ]
            ]
        ]
        return HapticPatternDescriptor(name: name, ahapDictionary: dict)
        #else
        return HapticPatternDescriptor(name: name)
        #endif
    }

    private static func crescendo(
        name: String,
        intensities: [Float],
        sharpness: Float,
        interval: TimeInterval
    ) -> HapticPatternDescriptor {
        #if canImport(CoreHaptics)
        let events: [[CHHapticPattern.Key: Any]] = intensities.enumerated().map { index, intensity in
            [
                CHHapticPattern.Key.event: [
                    CHHapticPattern.Key.eventType: CHHapticEvent.EventType.hapticTransient.rawValue,
                    CHHapticPattern.Key.time: Double(index) * interval,
                    CHHapticPattern.Key.eventParameters: [
                        [CHHapticPattern.Key.parameterID: CHHapticEvent.ParameterID.hapticIntensity.rawValue,
                         CHHapticPattern.Key.parameterValue: intensity],
                        [CHHapticPattern.Key.parameterID: CHHapticEvent.ParameterID.hapticSharpness.rawValue,
                         CHHapticPattern.Key.parameterValue: sharpness]
                    ]
                ]
            ]
        }
        let dict: [CHHapticPattern.Key: Any] = [.pattern: events]
        return HapticPatternDescriptor(name: name, ahapDictionary: dict)
        #else
        return HapticPatternDescriptor(name: name)
        #endif
    }

    private static func ramp(
        name: String,
        startIntensity: Float,
        endIntensity: Float,
        duration: TimeInterval
    ) -> HapticPatternDescriptor {
        #if canImport(CoreHaptics)
        let dict: [CHHapticPattern.Key: Any] = [
            .pattern: [
                [
                    CHHapticPattern.Key.event: [
                        CHHapticPattern.Key.eventType: CHHapticEvent.EventType.hapticContinuous.rawValue,
                        CHHapticPattern.Key.time: 0.0,
                        CHHapticPattern.Key.eventDuration: duration,
                        CHHapticPattern.Key.eventParameters: [
                            [CHHapticPattern.Key.parameterID: CHHapticEvent.ParameterID.hapticIntensity.rawValue,
                             CHHapticPattern.Key.parameterValue: startIntensity],
                            [CHHapticPattern.Key.parameterID: CHHapticEvent.ParameterID.hapticSharpness.rawValue,
                             CHHapticPattern.Key.parameterValue: 0.5]
                        ]
                    ]
                ]
            ],
            CHHapticPattern.Key.parameter: [
                [
                    CHHapticPattern.Key.parameterID: CHHapticDynamicParameter.ID.hapticIntensityControl.rawValue,
                    CHHapticPattern.Key.time: 0.0,
                    CHHapticPattern.Key.parameterCurveControlPoints: [
                        [CHHapticPattern.Key.time: 0.0, CHHapticPattern.Key.parameterValue: startIntensity],
                        [CHHapticPattern.Key.time: duration, CHHapticPattern.Key.parameterValue: endIntensity]
                    ]
                ]
            ]
        ]
        return HapticPatternDescriptor(name: name, ahapDictionary: dict)
        #else
        return HapticPatternDescriptor(name: name)
        #endif
    }
}
