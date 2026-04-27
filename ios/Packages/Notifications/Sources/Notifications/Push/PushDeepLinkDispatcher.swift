import Foundation
import Core

// MARK: - §21.8 Deep-link routing from push notifications
//
// Handles two scenarios:
//   A. App is running (foreground / background) — notification tap fires
//      `userNotificationCenter(_:didReceive:withCompletionHandler:)`.
//   B. Cold launch — the app is launched from a push tap; the notification
//      payload is in the launch options under `UIApplication.LaunchOptionsKey.remoteNotification`.
//
// In both cases we parse the `userInfo` into a `NotificationRoute`, optionally
// store the pending intent if auth is needed, then call the registered handler.
//
// Security — entity allowlist (§13.2 / §21.8):
//   Only entity types in `NotificationRoute` are parsed. Unknown types resolve
//   to `.unknown(entityType:)` which the app shell ignores gracefully — this
//   prevents injected entity-type strings from reaching the NavigationStack.
//
// Auth gate (§21.8):
//   If the token is absent (cold-launch before sign-in), the route is stored
//   in `PendingPushIntent` and replayed after successful authentication.

// MARK: - Pending push intent store

/// Stores a single pending deep-link for replay after authentication.
/// Persists to UserDefaults (no sensitive data — only entity type + Int64 id).
public struct PendingPushIntent: Sendable {
    public let route: NotificationRoute

    public func persist() {
        guard case .ticket(let id) = route else {
            // Simplified: only tickets persisted across cold launch for now.
            // Extend as needed per route case.
            UserDefaults.standard.removeObject(forKey: "notif.pendingRoute")
            return
        }
        UserDefaults.standard.set(["entity": "ticket", "id": id], forKey: "notif.pendingRoute")
    }

    public static func consume() -> PendingPushIntent? {
        defer { UserDefaults.standard.removeObject(forKey: "notif.pendingRoute") }
        guard let dict = UserDefaults.standard.dictionary(forKey: "notif.pendingRoute"),
              let entity = dict["entity"] as? String,
              let id = dict["id"] as? Int64 else { return nil }
        let route = NotificationRoute.from(userInfo: ["entityType": entity, "entityId": id])
        return route.map { PendingPushIntent(route: $0) }
    }
}

// MARK: - Dispatcher

/// Parses APNs payloads and routes to the app's NavigationStack.
///
/// Usage:
///   1. Inject `PushDeepLinkDispatcher.shared` into the app shell.
///   2. Register `onRoute` to perform NavigationStack pushes.
///   3. Call `dispatch(userInfo:isAuthenticated:)` from the notification delegate.
public final class PushDeepLinkDispatcher: @unchecked Sendable {
    public static let shared = PushDeepLinkDispatcher()

    /// Called on the main actor with the resolved route when auth is satisfied.
    @MainActor
    public var onRoute: ((NotificationRoute) -> Void)?

    private init() {}

    /// Dispatch a notification tap. Thread-safe; hops to MainActor for the handler.
    public func dispatch(userInfo: [AnyHashable: Any], isAuthenticated: Bool) {
        guard let route = NotificationRoute.from(userInfo: userInfo) else {
            AppLog.ui.debug("PushDeepLinkDispatcher: no route in payload")
            return
        }

        // Entity allowlist — reject unknown types
        if case .unknown(let type) = route {
            AppLog.ui.error("PushDeepLinkDispatcher: unknown entity type '\(type, privacy: .public)' — dropped")
            return
        }

        if isAuthenticated {
            Task { @MainActor in
                self.onRoute?(route)
            }
        } else {
            // Cold launch — auth not yet complete; store and replay after login.
            PendingPushIntent(route: route).persist()
            AppLog.ui.info("PushDeepLinkDispatcher: stored pending intent \(String(describing: route), privacy: .private)")
        }
    }

    /// Replay a stored pending intent after the user signs in.
    /// Call from the post-login completion handler.
    @MainActor
    public func replayPendingIfNeeded() {
        guard let pending = PendingPushIntent.consume() else { return }
        AppLog.ui.info("PushDeepLinkDispatcher: replaying pending intent")
        onRoute?(pending.route)
    }

    /// Dispatch from cold-launch options dictionary.
    /// Call from `application(_:didFinishLaunchingWithOptions:)`.
    public func dispatchFromLaunchOptions(_ options: [UIApplicationLaunchOptionsKey: Any]?, isAuthenticated: Bool) {
        guard let userInfo = options?[UIApplicationLaunchOptionsKey.remoteNotification] as? [AnyHashable: Any] else {
            return
        }
        dispatch(userInfo: userInfo, isAuthenticated: isAuthenticated)
    }
}

// Provide the UIApplicationLaunchOptionsKey type alias for platforms that have UIKit
#if canImport(UIKit)
import UIKit
typealias UIApplicationLaunchOptionsKey = UIApplication.LaunchOptionsKey
#else
struct UIApplicationLaunchOptionsKey: Hashable {
    static let remoteNotification = UIApplicationLaunchOptionsKey(rawValue: "UIApplicationLaunchOptionsRemoteNotificationKey")
    let rawValue: String
}
#endif
