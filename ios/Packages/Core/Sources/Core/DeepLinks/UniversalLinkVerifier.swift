import Foundation

// MARK: - UniversalLinkVerifier

/// Validates that a universal-link URL is structurally sound and hosted on a
/// domain covered by the app's `applinks:` entitlement before routing.
///
/// ## What this checks
/// 1. URL scheme is `https` — universal links are always HTTPS.
/// 2. Host is `app.bizarrecrm.com` or `<slug>.bizarrecrm.com`.
///    Self-hosted tenant domains are never in the entitlement; this guard
///    prevents accidentally routing an arbitrary HTTPS URL as a deep link.
/// 3. Path is not under `/public/` — customer-facing public pages must open
///    in Safari, not the staff app.
/// 4. The path can be parsed to a known `DeepLinkDestination` — unknown paths
///    should fall back to the web browser so Apple's AASA fallback can serve
///    the web page.
/// 5. URL does not carry script-injection payloads in query strings
///    (same rules as `DeepLinkValidator`).
///
/// ## Usage
/// ```swift
/// // In scene(_:continue:userActivity:)
/// guard let url = userActivity.webpageURL else { return false }
/// switch UniversalLinkVerifier.verify(url) {
/// case .valid(let destination):
///     DeepLinkRouter.shared.handle(url: url, destination: destination)
///     return true
/// case .fallbackToWeb:
///     // Return false — iOS opens the URL in Safari
///     return false
/// case .rejected(let reason):
///     AppLog.routing.warning("Universal link rejected: \(reason)")
///     return false
/// }
/// ```
public enum UniversalLinkVerifier {

    // MARK: - Verification result

    public enum VerificationResult: Sendable {
        /// URL is valid; use the associated destination for navigation.
        case valid(DeepLinkDestination)
        /// URL is structurally valid but no known app route exists.
        /// The caller should return `false` from `continue userActivity`
        /// so iOS opens the link in Safari.
        case fallbackToWeb(URL)
        /// URL is structurally invalid or carries a security risk.
        /// Do not open in Safari either; log and discard.
        case rejected(reason: String)
    }

    // MARK: - Allowed domains (must match Associated Domains entitlement)

    /// The primary host listed in `applinks:app.bizarrecrm.com`.
    public static let primaryHost = "app.bizarrecrm.com"

    /// The wildcard suffix listed in `applinks:*.bizarrecrm.com`.
    public static let wildcard    = ".bizarrecrm.com"

    // MARK: - Public API

    /// Verify `url` before routing it as a universal link.
    public static func verify(_ url: URL) -> VerificationResult {

        // 1. Must be HTTPS
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else {
            return .rejected(reason: "Universal link must be HTTPS, got '\(url.scheme ?? "nil")'")
        }

        // 2. Host must be in the entitlement
        guard let host = url.host?.lowercased() else {
            return .rejected(reason: "Universal link URL has no host")
        }
        guard isCoveredByEntitlement(host: host) else {
            return .rejected(reason: "Host '\(host)' is not covered by the applinks entitlement")
        }

        // 3. Block known-public customer-facing paths
        let firstPathSegment = url.pathComponents
            .filter { $0 != "/" }
            .first?
            .lowercased() ?? ""
        if publicSegments.contains(firstPathSegment) {
            return .fallbackToWeb(url)
        }

        // 4. Basic security: length + null bytes (lightweight version of DeepLinkValidator)
        let raw = url.absoluteString
        guard raw.count <= 2_048 else {
            return .rejected(reason: "Universal link URL exceeds maximum length")
        }
        guard !raw.contains("\0") && !raw.contains("%00") else {
            return .rejected(reason: "Universal link URL contains null bytes")
        }

        // 5. Parse to a known destination
        guard let destination = DeepLinkURLParser.parse(url) else {
            // Structurally valid bizarrecrm.com URL but no matching route —
            // let the web page handle it.
            return .fallbackToWeb(url)
        }

        // 6. Field-level validation of the parsed destination
        let fieldValidation = DeepLinkValidator.validate(destination: destination)
        guard fieldValidation.isValid else {
            if case .invalid(let reason) = fieldValidation {
                return .rejected(reason: "Destination field validation failed: \(reason)")
            }
            return .rejected(reason: "Destination field validation failed")
        }

        return .valid(destination)
    }

    // MARK: - Helpers

    /// Returns `true` when `host` matches `app.bizarrecrm.com` or any
    /// `<slug>.bizarrecrm.com` subdomain we provision for cloud tenants.
    public static func isCoveredByEntitlement(host: String) -> Bool {
        host == primaryHost || host.hasSuffix(wildcard)
    }

    /// Path segments that identify customer-facing public pages.
    /// These should open in Safari rather than the staff app.
    private static let publicSegments: Set<String> = [
        "track", "pay", "review", "book", "public"
    ]
}
