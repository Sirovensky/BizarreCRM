import Foundation
import UserNotifications
import Core

#if canImport(UIKit)
import UIKit
#endif

// MARK: - NotificationsAppDelegate

/// `UIApplicationDelegate` sub-delegate that owns the APNs lifecycle.
///
/// Wire from `BizarreCRMApp.swift` using `@UIApplicationDelegateAdaptor`:
///
/// ```swift
/// // In BizarreCRMApp.swift  (advisory-lock required — flag orchestrator)
/// @UIApplicationDelegateAdaptor(NotificationsAppDelegate.self)
/// var pushDelegate
/// ```
///
/// Then at startup (after successful login) call:
/// ```swift
/// NotificationsAppDelegate.shared.configure(
///     registrar: pushRegistrar,     // PushRegistrar actor
///     silentPushHandler: SilentPushHandler.shared,
///     notificationHandler: NotificationHandler.shared
/// )
/// ```
///
/// This file intentionally has zero direct dependency on `App/` targets so it
/// can live cleanly in the `Notifications` package without creating circular deps.
@MainActor
public final class NotificationsAppDelegate: NSObject {

    // MARK: - Shared

    /// Singleton set by `UIApplicationDelegate` adaptor machinery.
    /// Access this from app-level code to call `configure(...)`.
    public static var shared = NotificationsAppDelegate()

    // MARK: - Injected dependencies

    private var registrar: PushRegistrar?
    private var silentPushHandler: SilentPushHandler?

    // MARK: - Public configuration

    /// Inject the push registrar and silent-push handler.
    /// Must be called once after DI bootstrap, before any APNs callbacks can arrive.
    ///
    /// Also registers `NotificationHandler.shared` as the
    /// `UNUserNotificationCenter` delegate and calls
    /// `NotificationCategories.registerWithSystem()` so categories are live.
    public func configure(
        registrar: PushRegistrar,
        silentPushHandler: SilentPushHandler
    ) {
        self.registrar = registrar
        self.silentPushHandler = silentPushHandler

        // Register categories so action buttons appear on existing pushes.
        NotificationCategories.registerWithSystem()

        // Register this handler as the UNUserNotificationCenter delegate.
        // NotificationHandler.shared already holds the deep-link router after
        // the app calls NotificationHandler.shared.configure(deepLinkRouter:).
        UNUserNotificationCenter.current().delegate = NotificationHandler.shared
    }
}

// MARK: - UIApplicationDelegate

#if canImport(UIKit)
extension NotificationsAppDelegate: UIApplicationDelegate {

    /// APNs issued a device token.  Forward to `PushRegistrar`.
    public func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        guard let registrar else {
            AppLog.ui.error("NotificationsAppDelegate: registrar not configured — dropping token")
            return
        }
        Task {
            do {
                try await registrar.receiveDeviceToken(deviceToken)
            } catch {
                AppLog.ui.error("NotificationsAppDelegate: token upload failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// APNs registration failed (e.g. no entitlement on dev build).
    public func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        guard let registrar else { return }
        Task { await registrar.handleRegistrationFailure(error) }
    }

    /// Silent push (`content-available: 1`) — background data refresh.
    /// Must call `fetchCompletionHandler` within 30 seconds.
    public func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard let handler = silentPushHandler else {
            completionHandler(.noData)
            return
        }
        // Wrap userInfo in an @unchecked-Sendable box to satisfy Swift 6 data-race
        // check. The dictionary is read-only after the system hands it to us.
        let box = UncheckedUserInfo(userInfo: userInfo)
        Task {
            await handler.handle(userInfo: box.userInfo)
            completionHandler(.newData)
        }
    }
}

private struct UncheckedUserInfo: @unchecked Sendable {
    let userInfo: [AnyHashable: Any]
}
#endif
