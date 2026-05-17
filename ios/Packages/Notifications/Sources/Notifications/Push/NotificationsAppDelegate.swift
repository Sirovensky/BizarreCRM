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
        // BUGHUNT-2026-05-17: race the handler against a 25s timeout so we
        // ALWAYS call completionHandler within the 30s iOS budget. Previously
        // a hung syncNow() / refresh trigger meant we missed the deadline,
        // which iOS punishes by throttling future silent pushes for the app —
        // sometimes silently disabling them for hours. Box the call so only
        // the first call to completionHandler takes effect (calling it twice
        // is undefined behaviour and Apple's docs warn against it).
        let once = CompletionOnce(completionHandler)
        Task {
            await handler.handle(userInfo: box.userInfo)
            once.call(.newData)
        }
        Task {
            try? await Task.sleep(nanoseconds: 25_000_000_000) // 25s safety net
            // BUGHUNT-2026-05-17: report .failed on the timeout branch
            // instead of .newData. Telling iOS the fetch succeeded when it
            // actually timed out misleads the system's throttling
            // heuristics — iOS keeps sending silent pushes the app can't
            // complete, then eventually throttles harder when the "success"
            // claim doesn't match observed app behaviour. .failed is the
            // honest answer and lets iOS back off appropriately.
            once.call(.failed)
        }
    }
}

/// One-shot wrapper around `(UIBackgroundFetchResult) -> Void` so a timeout
/// race can fire either branch without invoking the system handler twice.
private final class CompletionOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: ((UIBackgroundFetchResult) -> Void)?
    init(_ handler: @escaping (UIBackgroundFetchResult) -> Void) {
        self.handler = handler
    }
    func call(_ result: UIBackgroundFetchResult) {
        lock.lock()
        let h = handler
        handler = nil
        lock.unlock()
        h?(result)
    }
}

private struct UncheckedUserInfo: @unchecked Sendable {
    let userInfo: [AnyHashable: Any]
}
#endif
