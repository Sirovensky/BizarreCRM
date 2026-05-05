// Core/A11y/A11yLiveRegion.swift
//
// SwiftUI helper for posting UIAccessibility notifications from view code.
// Wraps UIAccessibility.post(notification:argument:) behind a UIKit import
// so callers stay framework-agnostic.
//
// Requirements:
//   - iOS 17+ (UIKit always available in the app target)
//   - Swift 6 strict concurrency — all public APIs are @MainActor
//
// §26 A11y label catalog — live region helper

import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Posts UIAccessibility notifications from SwiftUI view code.
///
/// VoiceOver "live regions" are announcements pushed programmatically —
/// use them for transient status changes (save confirmation, sync progress,
/// error banners) that don't attach to a persistent UI element.
///
/// Example usage in a SwiftUI view:
/// ```swift
/// .onAppear {
///     A11yLiveRegion.announce("Invoice saved successfully")
/// }
/// Button("Save") {
///     save()
///     A11yLiveRegion.announce(A11yLabels.Invoices.paid)
/// }
/// ```
///
/// All methods are `@MainActor` because `UIAccessibility.post` must run
/// on the main thread.
public enum A11yLiveRegion: Sendable {

    // MARK: - Announcements

    /// Posts a `.announcement` notification to VoiceOver.
    ///
    /// VoiceOver reads the string aloud as soon as the current utterance
    /// finishes.  Use for one-shot confirmations and transient status changes.
    ///
    /// - Parameter message: The string to announce.  Should be concise (≤ 80 chars).
    @MainActor
    public static func announce(_ message: String) {
        guard !message.isEmpty else { return }
#if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: message)
#endif
    }

    /// Posts a `.announcement` notification after a short delay.
    ///
    /// Useful when the view update and the announcement race — the delay lets
    /// the view settle before VoiceOver speaks.
    ///
    /// - Parameters:
    ///   - message: The string to announce.
    ///   - delay:   Seconds to wait before posting.  Defaults to 0.3 s.
    @MainActor
    public static func announce(_ message: String, afterDelay delay: TimeInterval) {
        guard !message.isEmpty else { return }
        // Use a Task so we can delay without blocking the main run-loop.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            announce(message)
        }
    }

    // MARK: - Layout changed

    /// Posts a `.layoutChanged` notification, optionally moving VoiceOver focus
    /// to a specific element.
    ///
    /// Call this after inserting or removing significant portions of the UI
    /// (e.g., revealing a filter panel, dismissing an error banner).
    ///
    /// - Parameter element: The element to move focus to.  Pass `nil` to leave
    ///   focus where it is.
    @MainActor
    public static func layoutChanged(focusOn element: Any? = nil) {
#if canImport(UIKit)
        UIAccessibility.post(notification: .layoutChanged, argument: element)
#endif
    }

    // MARK: - Screen changed

    /// Posts a `.screenChanged` notification, optionally moving VoiceOver focus
    /// to a specific element.
    ///
    /// Call this after a full-screen navigation push/pop or a modal presentation
    /// so VoiceOver resets its reading position.
    ///
    /// - Parameter element: The element to move focus to.  Pass `nil` for default
    ///   behaviour (VoiceOver moves to the top of the new screen).
    @MainActor
    public static func screenChanged(focusOn element: Any? = nil) {
#if canImport(UIKit)
        UIAccessibility.post(notification: .screenChanged, argument: element)
#endif
    }

    // MARK: - Convenience helpers

    /// Announces a save-confirmation message for the given entity name.
    ///
    /// Produces strings like "Ticket saved" or "Invoice saved".
    ///
    /// - Parameter entityName: The localized entity name (e.g., "Ticket").
    @MainActor
    public static func announceSaved(entityName: String) {
        let message = NSLocalizedString(
            "a11y.liveRegion.saved",
            value: "\(entityName) saved",
            comment: "VoiceOver announcement after saving an entity (%@ = entity name)"
        )
        announce(message)
    }

    /// Announces a delete-confirmation message for the given entity name.
    ///
    /// - Parameter entityName: The localized entity name (e.g., "Customer").
    @MainActor
    public static func announceDeleted(entityName: String) {
        let message = NSLocalizedString(
            "a11y.liveRegion.deleted",
            value: "\(entityName) deleted",
            comment: "VoiceOver announcement after deleting an entity (%@ = entity name)"
        )
        announce(message)
    }

    /// Announces an error message prefixed with "Error:".
    ///
    /// - Parameter description: The localized error description.
    @MainActor
    public static func announceError(_ description: String) {
        guard !description.isEmpty else { return }
        let template = NSLocalizedString(
            "a11y.liveRegion.error",
            value: "Error: \(description)",
            comment: "VoiceOver announcement for an error (%@ = error description)"
        )
        announce(template)
    }
}
