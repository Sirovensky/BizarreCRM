import UIKit

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
