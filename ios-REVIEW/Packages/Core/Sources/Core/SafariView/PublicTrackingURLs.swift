import Foundation

// MARK: - PublicTrackingURLs

/// Typed builder for public-facing tracking links served under
/// `https://<baseURL>/track/`, `https://<baseURL>/pay/`, and
/// `https://<baseURL>/estimate/`.
///
/// These URLs are opened in `SFSafariViewController` (or a fallback WKWebView)
/// because they are intended for customers — not logged-in staff — and do not
/// require app authentication.
///
/// The `baseURL` defaults to `https://app.bizarrecrm.com` (the canonical
/// universal-link host) but can be overridden per-install to support
/// self-hosted tenants.
///
/// ## Example
/// ```swift
/// let url = PublicTrackingURLs.trackingURL(ticketId: "TKT-9901")
/// // → https://app.bizarrecrm.com/track/TKT-9901
/// ```
///
/// Thread-safe: stateless enum.
public enum PublicTrackingURLs {

    // MARK: - Default Base URL

    /// The canonical host used when no `baseURL` override is provided.
    public static let defaultBaseURL = URL(string: "https://\(DeepLinkURLParser.universalLinkHost)")!

    // MARK: - Public Tracking Link Builders

    /// Builds a `/track/:ticketId` public link.
    ///
    /// - Parameters:
    ///   - ticketId: The ticket identifier.
    ///   - baseURL:  Override base URL (default: `https://app.bizarrecrm.com`).
    /// - Returns: A percent-encoded URL, or `nil` if assembly fails.
    public static func trackingURL(
        ticketId: String,
        baseURL: URL = defaultBaseURL
    ) -> URL? {
        build(path: "track", id: ticketId, baseURL: baseURL)
    }

    /// Builds a `/pay/:linkId` public payment link.
    ///
    /// - Parameters:
    ///   - linkId:  The payment link identifier.
    ///   - baseURL: Override base URL (default: `https://app.bizarrecrm.com`).
    /// - Returns: A percent-encoded URL, or `nil` if assembly fails.
    public static func paymentURL(
        linkId: String,
        baseURL: URL = defaultBaseURL
    ) -> URL? {
        build(path: "pay", id: linkId, baseURL: baseURL)
    }

    /// Builds an `/estimate/:estimateId` public estimate preview link.
    ///
    /// - Parameters:
    ///   - estimateId: The estimate identifier.
    ///   - baseURL:    Override base URL (default: `https://app.bizarrecrm.com`).
    /// - Returns: A percent-encoded URL, or `nil` if assembly fails.
    public static func estimateURL(
        estimateId: String,
        baseURL: URL = defaultBaseURL
    ) -> URL? {
        build(path: "estimate", id: estimateId, baseURL: baseURL)
    }

    // MARK: - Private helpers

    /// Assembles `<baseURL>/<path>/<percent-encoded id>`.
    private static func build(
        path: String,
        id: String,
        baseURL: URL
    ) -> URL? {
        guard !id.isEmpty else { return nil }

        guard
            let encodedID = id.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            )
        else { return nil }

        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        comps?.path = "/\(path)/\(encodedID)"
        return comps?.url
    }
}
