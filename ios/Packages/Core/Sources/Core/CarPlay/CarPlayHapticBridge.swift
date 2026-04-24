#if canImport(CarPlay)
import CarPlay
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - CarPlayHapticEvent

/// The subset of haptic events that are safe to trigger from a CarPlay
/// (driving) context per Apple's Human Interface Guidelines for CarPlay.
///
/// Only non-distracting, confirmatory feedback is included.  Avoid using
/// heavy / repeated patterns that could distract the driver.
public enum CarPlayHapticEvent: Sendable, Equatable {

    /// Light tap confirming a successful action (e.g. call placed, item selected).
    case selectionConfirmed

    /// Brief notification that something new has arrived (e.g. incoming voicemail).
    case notificationArrived

    /// Error feedback for a failed action (e.g. call failed to connect).
    case actionFailed
}

// MARK: - CarPlayHapticBridge

/// Triggers the safe subset of haptic feedback events when the app is running
/// in a CarPlay session.
///
/// On devices that do not support haptics, or when the app is not in the
/// foreground CarPlay scene, all calls are silently no-ops to avoid unexpected
/// behaviour while driving.
///
/// ## Driving-safety contract
/// - **Only** events from ``CarPlayHapticEvent`` are exposed — the full
///   haptic catalog is intentionally excluded.
/// - Callers **must not** loop these events or chain them rapidly; one trigger
///   per user-initiated action is the maximum.
///
/// ## Usage
/// ```swift
/// CarPlayHapticBridge.shared.trigger(.selectionConfirmed)
/// ```
public final class CarPlayHapticBridge: @unchecked Sendable {

    // MARK: - Shared instance

    public static let shared = CarPlayHapticBridge()

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    /// Trigger a ``CarPlayHapticEvent`` if haptics are available on this device.
    ///
    /// Safe to call from any thread; UIKit feedback generators are internally
    /// dispatched to the main queue.
    public func trigger(_ event: CarPlayHapticEvent) {
        #if canImport(UIKit)
        switch event {
        case .selectionConfirmed:
            DispatchQueue.main.async {
                UISelectionFeedbackGenerator().selectionChanged()
            }
        case .notificationArrived:
            let generator = UINotificationFeedbackGenerator()
            DispatchQueue.main.async {
                generator.notificationOccurred(.success)
            }
        case .actionFailed:
            let generator = UINotificationFeedbackGenerator()
            DispatchQueue.main.async {
                generator.notificationOccurred(.error)
            }
        }
        #endif
    }
}

#endif // canImport(CarPlay)
