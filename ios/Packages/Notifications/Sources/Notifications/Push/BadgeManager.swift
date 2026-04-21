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
}
