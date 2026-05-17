import Foundation
import UserNotifications
import Core

// MARK: - BadgeCountProvider

/// Abstraction so BadgeManager can be tested without a live UNUserNotificationCenter.
public protocol BadgeCountProvider: Sendable {
    func setBadgeCount(_ count: Int) async throws
}

// MARK: - UNUserNotificationCenterBadgeProvider

/// Production implementation backed by `UNUserNotificationCenter`.
public struct UNUserNotificationCenterBadgeProvider: BadgeCountProvider {
    public init() {}

    public func setBadgeCount(_ count: Int) async throws {
        try await UNUserNotificationCenter.current().setBadgeCount(count)
    }
}

// MARK: - BadgeManager

/// Manages the app-icon badge count.
///
/// The count is derived from:
///   - Unread notifications inbox count
///   - Unread SMS count
///
/// Callers update the relevant count by calling `updateBadgeCount(unreadCount:)`.
/// The manager persists the last known value in memory for display in tab bars.
///
/// Usage:
/// ```swift
/// // After a sync completes:
/// await BadgeManager.shared.updateBadgeCount(unreadCount: totalUnread)
/// ```
@MainActor
public final class BadgeManager {

    // MARK: - Shared

    public static let shared = BadgeManager()

    // MARK: - Observable state

    /// Last count set on the badge. Other UI elements (tab bar) can read this.
    public private(set) var currentBadgeCount: Int = 0

    // MARK: - Dependencies

    private let provider: any BadgeCountProvider

    // MARK: - Init

    public init(provider: any BadgeCountProvider = UNUserNotificationCenterBadgeProvider()) {
        self.provider = provider
    }

    // MARK: - Public API

    /// Set the badge to `unreadCount`. Clamps to 0 and no-ops if unchanged.
    /// Silently ignores errors (badge is non-critical UX).
    public func updateBadgeCount(unreadCount: Int) async {
        let clamped = max(0, unreadCount)
        guard clamped != currentBadgeCount else { return }
        do {
            try await provider.setBadgeCount(clamped)
            currentBadgeCount = clamped
        } catch {
            AppLog.ui.error("BadgeManager: setBadgeCount failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Clears the badge (sets to 0).
    public func clearBadge() async {
        await updateBadgeCount(unreadCount: 0)
    }

    // MARK: - Cold-launch badge clear (§13.4)

    /// Call once during cold launch — before the first sync — to reset a stale
    /// badge that may have been set by a previous session and never reconciled.
    ///
    /// The badge is immediately zeroed so the user sees a clean state while the
    /// app fetches the authoritative unread count from the server.  Once the
    /// sync completes callers must call `updateBadgeCount(unreadCount:)` with
    /// the live count to restore the correct value.
    ///
    /// This prevents the app icon from showing a stale number after:
    /// - A reinstall (Keychain tokens survived but badge count did not reset).
    /// - A force-quit while the badge counter was elevated.
    /// - A notification that was read on another device / web but the badge
    ///   never decremented locally.
    ///
    /// Should be invoked from the app's cold-start path (e.g. `AppState.init`
    /// or `SessionBootstrapper.coldStart()`) before any network calls complete.
    public func clearBadgeOnColdLaunch() async {
        // BUGHUNT-2026-05-17: previously this returned early when
        // `currentBadgeCount == 0` — but the in-memory cache is ALWAYS 0 at
        // cold launch (struct just initialised). The OS-level badge from a
        // previous session could be 5+, but we'd skip the clear and the
        // user would stare at a stale red dot until the first server sync
        // finished. That defeated the entire purpose of the function.
        //
        // Unconditionally drive the OS badge to 0 — skip the `updateBadge`
        // short-circuit by calling the provider directly, then sync the
        // in-memory cache to match.
        AppLog.ui.info("BadgeManager.clearBadgeOnColdLaunch: clearing OS badge regardless of in-memory cache")
        do {
            try await provider.setBadgeCount(0)
            currentBadgeCount = 0
        } catch {
            AppLog.ui.error("BadgeManager.clearBadgeOnColdLaunch: setBadgeCount failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
