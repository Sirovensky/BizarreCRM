import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - §26.1 VoiceOver-gated announcement
//
// Posts `.announcement` notifications **only when VoiceOver is running**.
// Calling sites can fire-and-forget without burning work for sighted users:
// when VoiceOver is off the helper is a cheap no-op (single `Bool` read on
// the main actor, no Task / no UIKit post).
//
// Usage:
// ```swift
// // After async success:
// VoiceOverAnnouncer.announceIfRunning("Ticket created")
//
// // After async failure:
// VoiceOverAnnouncer.announceErrorIfRunning(error.localizedDescription)
// ```
//
// Pair with `A11yLiveRegion` for ungated announcements (e.g. live-region
// totals where the announcement is already cheap and may also be useful for
// Switch Control). Use this gated variant when the announcement would be
// pure waste outside VoiceOver — async toasts, success confirmations, etc.

public enum VoiceOverAnnouncer: Sendable {

    /// Returns `true` when iOS reports VoiceOver as the active assistive
    /// technology. Cheap (`UIAccessibility.isVoiceOverRunning` is a synchronous
    /// flag) so callers can branch on it without caching.
    @MainActor
    public static var isRunning: Bool {
        #if canImport(UIKit)
        return UIAccessibility.isVoiceOverRunning
        #else
        return false
        #endif
    }

    /// Posts a `.announcement` notification **iff VoiceOver is running**.
    ///
    /// - Parameter message: text to announce; ignored when empty or when
    ///   VoiceOver is off.
    @MainActor
    public static func announceIfRunning(_ message: String) {
        guard !message.isEmpty else { return }
        #if canImport(UIKit)
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
        #endif
    }

    /// Posts an error announcement **iff VoiceOver is running**, prefixed with
    /// the localized "Error:" label so the user knows the source.
    @MainActor
    public static func announceErrorIfRunning(_ description: String) {
        guard !description.isEmpty else { return }
        #if canImport(UIKit)
        guard UIAccessibility.isVoiceOverRunning else { return }
        let template = NSLocalizedString(
            "a11y.liveRegion.error",
            value: "Error: \(description)",
            comment: "VoiceOver announcement for an error (%@ = error description)"
        )
        UIAccessibility.post(notification: .announcement, argument: template)
        #endif
    }
}
