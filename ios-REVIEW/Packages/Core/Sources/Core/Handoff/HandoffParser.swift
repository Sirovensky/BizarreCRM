import Foundation

// MARK: - HandoffParser

/// Converts an incoming `NSUserActivity` back into a `DeepLinkDestination`.
///
/// The parser implements a two-tier strategy:
/// 1. **`userInfo` tier** — reads the `HandoffBuilder.Keys.destinationURL`
///    key set by `HandoffBuilder`. This is the preferred path because it
///    preserves the exact destination without re-parsing.
/// 2. **`webpageURL` fallback** — if `userInfo` is missing the destination
///    key (e.g. activity originated on an older app version), the
///    `webpageURL` is passed through `DeepLinkURLParser`.
///
/// Returns `nil` when neither tier can produce a valid destination.
///
/// Thread-safe: stateless enum.
public enum HandoffParser {

    // MARK: - Public API

    /// Parse `activity` into a `DeepLinkDestination`.
    ///
    /// - Parameter activity: An `NSUserActivity` received from Handoff.
    /// - Returns: The matching destination, or `nil` if unrecognised.
    public static func destination(
        from activity: NSUserActivity
    ) -> DeepLinkDestination? {
        // Tier 1: structured userInfo URL string
        if let info = activity.userInfo as? [String: String],
           let urlString = info[HandoffBuilder.Keys.destinationURL],
           let url = URL(string: urlString),
           let destination = DeepLinkURLParser.parse(url) {
            return destination
        }

        // Tier 2: webpageURL fallback
        if let webURL = activity.webpageURL,
           let destination = DeepLinkURLParser.parse(webURL) {
            return destination
        }

        return nil
    }

    // MARK: - Eligibility guard

    /// Parse `activity` and return the destination only when it is
    /// Handoff-eligible, discarding private or unsupported screens.
    ///
    /// Use this variant in `scene(_:continue:)` / `application(_:continue:restorationHandler:)`
    /// to silently drop activities that should not trigger navigation.
    public static func eligibleDestination(
        from activity: NSUserActivity
    ) -> DeepLinkDestination? {
        guard let destination = destination(from: activity) else { return nil }
        guard HandoffEligibility.isEligible(destination) else { return nil }
        return destination
    }
}
