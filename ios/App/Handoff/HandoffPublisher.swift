import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Activity type constants

/// All `NSUserActivity` types registered in `NSUserActivityTypes` (Info.plist).
public enum HandoffActivityType {
    public static let ticketView    = "com.bizarrecrm.ticket.view"
    public static let customerView  = "com.bizarrecrm.customer.view"
    public static let invoiceView   = "com.bizarrecrm.invoice.view"
    public static let dashboard     = "com.bizarrecrm.dashboard"
}

// MARK: - HandoffPublisher

/// Creates and manages `NSUserActivity` objects for Handoff and Siri suggestions.
///
/// Retain the returned `NSUserActivity` for as long as the user is on that screen.
/// Releasing it (or calling `invalidate()`) ends the Handoff advertisement.
///
/// **Wiring (do NOT edit BizarreCRMApp.swift — paste these snippets):**
///
/// ```swift
/// // BizarreCRMApp.body — inside WindowGroup body, after existing modifiers:
/// .userActivity(HandoffActivityType.ticketView) { activity in
///     // SwiftUI will populate this when the view emits userActivity(…)
/// }
/// .onContinueUserActivity(HandoffActivityType.ticketView) { activity in
///     HandoffReceiver.shared.handle(activity)
/// }
/// .onContinueUserActivity(HandoffActivityType.customerView) { activity in
///     HandoffReceiver.shared.handle(activity)
/// }
/// .onContinueUserActivity(HandoffActivityType.invoiceView) { activity in
///     HandoffReceiver.shared.handle(activity)
/// }
/// .onContinueUserActivity(HandoffActivityType.dashboard) { activity in
///     HandoffReceiver.shared.handle(activity)
/// }
/// ```
@MainActor
public final class HandoffPublisher {

    // MARK: Singleton

    public static let shared = HandoffPublisher()

    private init() {}

    // MARK: Public API

    /// Create (and make current) a `NSUserActivity` for Handoff.
    ///
    /// - Parameters:
    ///   - activityType: One of the `HandoffActivityType` constants.
    ///   - title:        Human-readable title shown in the Handoff dock icon.
    ///   - deepLinkURL:  App deep link URL (`bizarrecrm://` or universal link)
    ///                   stored in `userInfo` so `HandoffReceiver` can route it.
    ///   - entityId:     Optional opaque entity identifier stored in `userInfo`.
    /// - Returns: The live `NSUserActivity`. Retain it for the duration of the screen.
    @discardableResult
    public func publish(
        activityType: String,
        title: String,
        deepLinkURL: URL,
        entityId: String? = nil
    ) -> NSUserActivity {
        let activity = NSUserActivity(activityType: activityType)
        activity.title = title
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch  = true
        activity.isEligibleForPrediction = true

        var info: [String: Any] = [
            "deepLinkURL": deepLinkURL.absoluteString
        ]
        if let entityId {
            info["entityId"] = entityId
        }
        activity.userInfo = info
        activity.webpageURL = asUniversalLink(deepLinkURL)
        activity.becomeCurrent()
        return activity
    }

    // MARK: Helpers

    /// Converts a `bizarrecrm://` URL to its `https://app.bizarrecrm.com` equivalent
    /// so macOS/iOS can show the Handoff icon and continue via web if the app is absent.
    private func asUniversalLink(_ url: URL) -> URL? {
        guard
            url.scheme?.lowercased() == "bizarrecrm",
            let host = url.host
        else {
            // Already a universal link or unknown — pass through.
            return url.scheme?.hasPrefix("http") == true ? url : nil
        }
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host   = "app.bizarrecrm.com"
        // Preserve path: /slug/resource/id
        let path = "/\(host)\(url.path)"
        comps.path   = path
        comps.query  = url.query
        return comps.url
    }
}
