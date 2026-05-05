import UIKit
import Observation

// MARK: - MultiWindowCoordinator

/// Coordinates opening entity detail records in dedicated iPad scenes.
///
/// Each `open*` method spawns a new `UIWindowScene` by requesting a new scene
/// session via `UIApplication.shared.requestSceneSessionActivation(_:userActivity:options:)`.
/// The route is encoded into an `NSUserActivity` and handed to `SceneDelegate`
/// via the system scene activation lifecycle.
///
/// **Usage**
/// ```swift
/// MultiWindowCoordinator.shared.openTicketDetail(id: "abc123")
/// ```
///
/// **Scene wiring** — `BizarreCRMApp.swift` must declare a `WindowGroup(id: "detail")`
/// so SwiftUI can fulfil the scene request. See `DetailWindowScene.swift` for the body.
@MainActor
@Observable
public final class MultiWindowCoordinator: @unchecked Sendable {

    // MARK: Singleton

    public static let shared = MultiWindowCoordinator()

    // MARK: Internal state

    /// Most recently requested deep-link route; observed by detail scenes.
    public private(set) var pendingRoute: String?

    private init() {}

    // MARK: - Public API

    /// Open a Ticket detail record in a new iPad window.
    /// - Parameter id: The server-assigned ticket identifier.
    public func openTicketDetail(id: String) {
        openDetailScene(routeURL: "bizarrecrm://ticket/\(id)")
    }

    /// Open a Customer detail record in a new iPad window.
    /// - Parameter id: The server-assigned customer identifier.
    public func openCustomerDetail(id: String) {
        openDetailScene(routeURL: "bizarrecrm://customer/\(id)")
    }

    /// Open an Invoice detail record in a new iPad window.
    /// - Parameter id: The server-assigned invoice identifier.
    public func openInvoiceDetail(id: String) {
        openDetailScene(routeURL: "bizarrecrm://invoice/\(id)")
    }

    // MARK: - Private helpers

    private func openDetailScene(routeURL: String) {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }

        let activity = NSUserActivity(activityType: ActivityTypes.detailView)
        activity.userInfo = ["deepLinkURL": routeURL]
        activity.isEligibleForHandoff = false
        activity.isEligibleForSearch = false

        let options = UIWindowScene.ActivationRequestOptions()
        options.requestingScene = nil // let the system place the window

        UIApplication.shared.requestSceneSessionActivation(
            nil,
            userActivity: activity,
            options: options,
            errorHandler: { error in
                // Non-fatal: log and continue; detail is always available
                // in the primary window as a navigation push fallback.
                print("[MultiWindowCoordinator] scene activation error: \(error.localizedDescription)")
            }
        )

        pendingRoute = routeURL
    }
}

// MARK: - Activity type constants

public enum ActivityTypes {
    public static let detailView = "com.bizarrecrm.activity.detailView"
}
