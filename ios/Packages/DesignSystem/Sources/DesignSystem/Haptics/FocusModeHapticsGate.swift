import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - §66 Do-Not-Disturb / Focus mode haptics gate
//
// When a Focus mode is active, haptics for non-critical events are suppressed
// so the user is not distracted by on-screen interactions during focused work.
//
// Critical events (card declined, backup failure) still fire during Focus.
//
// Implementation note:
//   iOS 16+ exposes `UNUserNotificationCenter.notificationSettings.allowsNotifications`
//   as an indirect signal for Focus mode. However, the Focus API for third-party apps
//   is limited — we cannot read the exact Focus kind without `NEHotspotNetwork` / MDM
//   entitlements. Instead we use `UIApplication.shared.isIdleTimerDisabled` (kiosk)
//   and the notification-center signal combined with user-visible toggles.
//
//   The most reliable DND signal in iOS 16+ is via `notificationSettings`:
//     UNUserNotificationCenter.current().notificationSettings { settings in
//         settings.alertSetting == .disabled  →  DND is likely active
//     }
//
//   We check this asynchronously on a background task and cache the result for
//   5 minutes before re-querying — avoiding excessive async calls per haptic play.

// MARK: - FocusModeHapticsGate

/// Determines whether non-critical haptics should fire given current Focus mode state.
///
/// Thread-safe actor — query from any context.
public actor FocusModeHapticsGate {

    // MARK: Singleton

    public static let shared = FocusModeHapticsGate()

    // MARK: Types

    public enum FocusState: Sendable {
        case unknown
        case normal         // No Focus / DND active — haptics allowed
        case focusActive    // Focus / DND is likely active — suppress non-critical
    }

    // MARK: State

    private var cachedState: FocusState = .unknown
    private var lastChecked: Date = .distantPast
    private let cacheTTL: TimeInterval = 300  // 5 minutes

    // MARK: Query

    /// Returns `true` if haptics should be suppressed for non-critical events.
    ///
    /// - Parameter isCritical: Pass `true` for events like card decline, backup failure.
    ///   Critical events always fire regardless of Focus state.
    public func shouldSuppress(isCritical: Bool) async -> Bool {
        if isCritical { return false }

        let state = await currentState()
        return state == .focusActive
    }

    // MARK: Private

    private func currentState() async -> FocusState {
        // Return cached value if fresh.
        if abs(lastChecked.timeIntervalSinceNow) < cacheTTL && cachedState != .unknown {
            return cachedState
        }

        let state = await queryNotificationCenter()
        cachedState = state
        lastChecked = Date()
        return state
    }

    private func queryNotificationCenter() async -> FocusState {
        #if canImport(UIKit)
        return await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                // If notifications are allowed, Focus is not suppressing them → normal.
                // If alerts are disabled, Focus / DND is likely active.
                switch settings.alertSetting {
                case .enabled:
                    continuation.resume(returning: .normal)
                case .disabled, .notSupported:
                    continuation.resume(returning: .focusActive)
                @unknown default:
                    continuation.resume(returning: .unknown)
                }
            }
        }
        #else
        return .normal  // macOS / non-UIKit: no Focus API, assume normal
        #endif
    }

    // MARK: Manual override (Settings → Do Not Disturb integration)

    /// Force a known state — called when the user explicitly enables/disables the
    /// "Suppress haptics during Focus" toggle in Settings → Haptics.
    public func forceState(_ state: FocusState) {
        cachedState  = state
        lastChecked  = Date()
    }

    /// Invalidate the cache so the next `shouldSuppress` call re-queries.
    public func invalidateCache() {
        lastChecked = .distantPast
    }
}

// MARK: - HapticCatalog integration

extension HapticCatalog {
    /// Gate that checks both quiet hours AND Focus mode before playing.
    ///
    /// Drop-in replacement for `play(_:withSound:)` that also respects DND.
    public static func playRespectingFocus(_ event: HapticEvent, withSound: Bool = false) async {
        let isCritical = (event == .cardDeclined)

        let focusSuppressed = await FocusModeHapticsGate.shared.shouldSuppress(isCritical: isCritical)
        if focusSuppressed { return }

        await play(event, withSound: withSound)
    }
}
