import Foundation

// MARK: - HandoffBuilder

/// Factory that converts a `DeepLinkDestination` into an `NSUserActivity`
/// ready for Handoff.
///
/// The produced activity embeds a universal-link URL in its
/// `webpageURL` property so that:
/// 1. iOS/macOS Handoff can transfer it to another device running the app.
/// 2. If the receiving device does not have the app installed, Safari opens
///    `app.bizarrecrm.com/<slug>/…` instead.
///
/// ## Usage
/// ```swift
/// if let activity = HandoffBuilder.build(from: .ticket(tenantSlug: "acme", id: "T-1")) {
///     userActivity = activity
///     activity.becomeCurrent()
/// }
/// ```
///
/// ## Metadata stored in `userInfo`
/// | Key | Value |
/// |-----|-------|
/// | `HandoffBuilder.Keys.tenantSlug` | Tenant slug string |
/// | `HandoffBuilder.Keys.destination` | `DeepLinkBuilder`-produced URL string |
///
/// Thread-safe: stateless enum.
public enum HandoffBuilder {

    // MARK: - UserInfo keys

    /// Namespace for well-known `userInfo` dictionary keys.
    public enum Keys {
        /// Tenant slug identifying which organisation's data is being viewed.
        public static let tenantSlug = "com.bizarrecrm.handoff.tenantSlug"
        /// Canonical universal-link URL for the displayed record.
        public static let destinationURL = "com.bizarrecrm.handoff.destinationURL"
    }

    // MARK: - Public API

    /// Build an `NSUserActivity` for `destination`, or `nil` when the
    /// destination is not Handoff-eligible (see `HandoffEligibility`).
    ///
    /// - Parameter destination: The screen to represent.
    /// - Returns: A configured `NSUserActivity`, or `nil`.
    public static func build(from destination: DeepLinkDestination) -> NSUserActivity? {
        guard let activityType = HandoffEligibility.activityType(for: destination) else {
            return nil
        }

        let activity = NSUserActivity(
            activityType: activityType.activityTypeIdentifier
        )

        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch  = true

        // Embed a universal-link URL so Safari can open it as a fallback.
        if let webURL = DeepLinkBuilder.build(destination, form: .universalLink) {
            activity.webpageURL = webURL
        }

        // Store structured metadata for the receiving end of the Handoff.
        var info: [String: String] = [:]

        if let slug = destination.tenantSlug {
            info[Keys.tenantSlug] = slug
        }

        if let urlString = DeepLinkBuilder.build(
            destination,
            form: .universalLink
        )?.absoluteString {
            info[Keys.destinationURL] = urlString
        }

        activity.userInfo = info
        activity.title = activityTitle(for: destination)

        return activity
    }

    // MARK: - Private helpers

    private static func activityTitle(for destination: DeepLinkDestination) -> String {
        switch destination {
        case .ticket(_, let id):
            return "Ticket \(id)"
        case .customer(_, let id):
            return "Customer \(id)"
        case .invoice(_, let id):
            return "Invoice \(id)"
        case .estimate(_, let id):
            return "Estimate \(id)"
        default:
            return "BizarreCRM"
        }
    }
}
