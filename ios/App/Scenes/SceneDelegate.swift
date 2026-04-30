import UIKit

// MARK: - SceneStateRestorer (§22.4)

public enum SceneStateRestorer {
    public static let activityType = "com.bizarrecrm.sceneState"
    private enum Key { static let deepLinkURL = "deepLinkURL" }
    public static func save(routeURL: String, session: UISceneSession) -> NSUserActivity {
        let a = NSUserActivity(activityType: activityType)
        a.isEligibleForHandoff = false; a.isEligibleForSearch = false
        a.userInfo = [Key.deepLinkURL: routeURL]
        return a
    }
    public static func restore(from activity: NSUserActivity) -> String? {
        guard activity.activityType == activityType else { return nil }
        return activity.userInfo?[Key.deepLinkURL] as? String
    }
}

// MARK: - SceneDelegate

/// UIKit scene delegate wiring.
///
/// Handles URL context and Handoff `NSUserActivity` arrivals for scenes
/// that SwiftUI's `@UIApplicationDelegateAdaptor` / `WindowGroup` do not
/// intercept (e.g. secondary detail windows opened via
/// `MultiWindowCoordinator`).
///
/// **Registration** — In `BizarreCRMApp.swift` add:
/// ```swift
/// @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
/// ```
/// and in `AppDelegate`:
/// ```swift
/// func application(_ application: UIApplication,
///                  configurationForConnecting connectingSceneSession: UISceneSession,
///                  options: UIScene.ConnectionOptions) -> UISceneConfiguration {
///     let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
///     config.delegateClass = SceneDelegate.self
///     return config
/// }
/// ```
public final class SceneDelegate: NSObject, UIWindowSceneDelegate {

    public var window: UIWindow?

    // MARK: UIWindowSceneDelegate

    public func scene(
        _ scene: UIScene,
        openURLContexts URLContexts: Set<UIOpenURLContext>
    ) {
        guard let firstURL = URLContexts.first?.url else { return }
        Task { @MainActor in
            DeepLinkRouter.shared.handle(firstURL)
        }
    }

    public func scene(
        _ scene: UIScene,
        continue userActivity: NSUserActivity
    ) {
        Task { @MainActor in
            HandoffReceiver.shared.handle(userActivity)
        }
    }

    public func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        // §22.4 — Stage Manager scene-restoration: if the system preserved a
        // state-restoration activity for this session, replay it first so the
        // window reopens at the same route it was on before eviction.
        if let restorationActivity = session.stateRestorationActivity,
           let urlString = SceneStateRestorer.restore(from: restorationActivity),
           let url = URL(string: urlString) {
            Task { @MainActor in
                DeepLinkRouter.shared.handle(url)
            }
            return
        }

        // Hand off any user activity that was attached at scene creation
        // (e.g. from MultiWindowCoordinator's NSUserActivity payload).
        if let activity = connectionOptions.userActivities.first {
            Task { @MainActor in
                HandoffReceiver.shared.handle(activity)
            }
        } else if let firstURL = connectionOptions.urlContexts.first?.url {
            Task { @MainActor in
                DeepLinkRouter.shared.handle(firstURL)
            }
        }
    }
}
