import Foundation
import CoreSpotlight
import Core

// MARK: - SpotlightActivityHandler

/// Parses an `NSUserActivity` delivered when the user taps a BizarreCRM
/// result in Spotlight search, and returns a typed `SpotlightEntityReference`.
///
/// **Usage in the app-shell** (e.g. `WindowGroup.onContinueUserActivity`):
/// ```swift
/// .onContinueUserActivity(CSSearchableItemActionType) { activity in
///     if let ref = SpotlightActivityHandler.entityReference(from: activity) {
///         appRouter.navigate(to: SpotlightDeepLinkResolver.destination(for: ref))
///     }
/// }
/// ```
///
/// The handler is `enum`-namespaced (no stored state) so it can be called from
/// any concurrency context without isolation concerns.
public enum SpotlightActivityHandler {

    // MARK: - Public API

    /// Extract a `SpotlightEntityReference` from an `NSUserActivity` that was
    /// delivered via the CoreSpotlight action type.
    ///
    /// Returns `nil` if:
    /// - The activity type is not `CSSearchableItemActionType`.
    /// - The unique-identifier key is absent or malformed.
    /// - The domain segment does not match a known `EntityKind`.
    /// - The ID segment cannot be parsed as `Int64`.
    ///
    /// - Parameter activity: The `NSUserActivity` passed to
    ///   `application(_:continue:restorationHandler:)` or SwiftUI's
    ///   `onContinueUserActivity` modifier.
    /// - Returns: A `SpotlightEntityReference`, or `nil` on parse failure.
    public static func entityReference(from activity: NSUserActivity) -> SpotlightEntityReference? {
        guard activity.activityType == CSSearchableItemActionType else {
            AppLog.ui.debug("SpotlightActivityHandler: unexpected activity type '\(activity.activityType, privacy: .public)'")
            return nil
        }

        guard let uniqueId = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else {
            AppLog.ui.warning("SpotlightActivityHandler: missing CSSearchableItemActivityIdentifier")
            return nil
        }

        return parse(uniqueIdentifier: uniqueId)
    }

    // MARK: - Internal parsing

    /// Parse a raw unique identifier string into a `SpotlightEntityReference`.
    ///
    /// Expected format: `"bizarrecrm.<kind>.<id>"`
    /// - Parameter uniqueIdentifier: The raw identifier string.
    static func parse(uniqueIdentifier: String) -> SpotlightEntityReference? {
        // Expected components: ["bizarrecrm", kind, id]
        let parts = uniqueIdentifier.split(separator: ".", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0] == "bizarrecrm" else {
            AppLog.ui.warning("SpotlightActivityHandler: malformed identifier '\(uniqueIdentifier, privacy: .public)'")
            return nil
        }

        let kindRaw = String(parts[1])
        let idRaw   = String(parts[2])

        guard let kind = SpotlightEntityReference.EntityKind(rawValue: kindRaw) else {
            AppLog.ui.warning("SpotlightActivityHandler: unknown entity kind '\(kindRaw, privacy: .public)'")
            return nil
        }

        guard let entityId = Int64(idRaw) else {
            AppLog.ui.warning("SpotlightActivityHandler: invalid entity id '\(idRaw, privacy: .public)'")
            return nil
        }

        return SpotlightEntityReference(kind: kind, entityId: entityId, uniqueIdentifier: uniqueIdentifier)
    }
}
