import UIKit
import Foundation

// MARK: - SceneStateRestorer
//
// §22.4 — "Scene state restored per-window on relaunch."
//
// The system calls `stateRestorationActivity(for:)` on the scene delegate
// before a scene is discarded (background eviction, user swipe-close, etc.).
// On relaunch the stored `NSUserActivity` is delivered back through
// `scene(_:willConnectTo:options:)` in `SceneDelegate`.
//
// Strategy:
//   1. Each active window's deep-link route is written into a per-session
//      `NSUserActivity` via `SceneStateRestorer.save(route:for:)`.
//   2. On relaunch `SceneStateRestorer.restore(from:)` extracts the route
//      string and returns it; callers pass it into `DeepLinkRouter.shared`.
//
// The primary window (dashboard) never needs this — it starts at its default
// destination.  Only secondary detail windows (ticket/customer/invoice opened
// via `MultiWindowCoordinator`) carry state.

public enum SceneStateRestorer {

    // MARK: - Activity type

    /// `NSUserActivity` type used exclusively for scene-state snapshots.
    /// Must be listed in `NSUserActivityTypes` in `Info.plist`.
    public static let activityType = "com.bizarrecrm.sceneState"

    // MARK: - UserInfo keys

    private enum Key {
        static let deepLinkURL = "deepLinkURL"
        static let sessionId   = "sessionPersistentId"
    }

    // MARK: - Save

    /// Create an `NSUserActivity` encoding the current window's deep-link route.
    ///
    /// Call this from `SceneDelegate.stateRestorationActivity(for:)`:
    /// ```swift
    /// func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
    ///     guard let routeURL = MultiWindowCoordinator.shared.pendingRoute else { return nil }
    ///     return SceneStateRestorer.save(routeURL: routeURL, session: scene.session)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - routeURL:  The `bizarrecrm://` deep-link URL string for this window.
    ///   - session:   The `UISceneSession` whose `persistentIdentifier` tags
    ///               the activity so it can be matched on relaunch.
    /// - Returns: A configured `NSUserActivity` ready to return from
    ///           `stateRestorationActivity(for:)`.
    public static func save(routeURL: String, session: UISceneSession) -> NSUserActivity {
        let activity = NSUserActivity(activityType: activityType)
        activity.title = "BizarreCRM window"
        activity.isEligibleForHandoff = false
        activity.isEligibleForSearch  = false
        activity.userInfo = [
            Key.deepLinkURL: routeURL,
            Key.sessionId:   session.persistentIdentifier,
        ]
        return activity
    }

    // MARK: - Restore

    /// Extract the stored deep-link URL string from a restoration activity.
    ///
    /// Call inside `SceneDelegate.scene(_:willConnectTo:options:)` when the
    /// connection options carry a restoration activity:
    /// ```swift
    /// if let activity = session.stateRestorationActivity {
    ///     if let urlString = SceneStateRestorer.restore(from: activity) {
    ///         DeepLinkRouter.shared.handle(URL(string: urlString)!)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter activity: The `NSUserActivity` from `UISceneSession.stateRestorationActivity`.
    /// - Returns: The deep-link URL string, or `nil` if the activity was not
    ///           created by this restorer or contains no URL.
    public static func restore(from activity: NSUserActivity) -> String? {
        guard activity.activityType == activityType else { return nil }
        return activity.userInfo?[Key.deepLinkURL] as? String
    }
}

// MARK: - SceneDelegate extension

extension SceneDelegate {

    /// Returns the state-restoration activity for the given scene.
    ///
    /// The system calls this when a scene is about to be discarded so it can
    /// persist the scene's current state.  On next launch the stored activity
    /// arrives in `UISceneSession.stateRestorationActivity`.
    public func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        guard let urlString = MultiWindowCoordinator.shared.pendingRoute else {
            return nil
        }
        return SceneStateRestorer.save(routeURL: urlString, session: scene.session)
    }
}
