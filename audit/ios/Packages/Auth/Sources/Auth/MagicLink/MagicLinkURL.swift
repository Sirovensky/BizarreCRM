import Foundation

/// Parses magic-link deep-links into their one-time token.
///
/// Accepted forms:
///   - `bizarrecrm://auth/magic?token=<TOKEN>`
///     → host: "auth", path: "/magic"
///   - `https://app.bizarrecrm.com/auth/magic?token=<TOKEN>`
///     → host: "app.bizarrecrm.com", path: "/auth/magic"
///
/// Expose this helper to `DeepLinkRouter` without wiring the router here.
/// The router registers a handler that calls `MagicLinkURL.token(from:)`.
public enum MagicLinkURL {

    private static let customScheme    = "bizarrecrm"
    private static let customHost      = "auth"
    private static let customPath      = "/magic"
    private static let universalHost   = "app.bizarrecrm.com"
    private static let universalPath   = "/auth/magic"
    private static let tokenQueryKey   = "token"

    /// Returns the extracted token if `url` is a recognised magic-link URL,
    /// otherwise returns `nil`.
    public static func token(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        guard isMatch(components) else { return nil }
        return components.queryItems?.first(where: { $0.name == tokenQueryKey })?.value
    }

    /// Returns `true` if the URL is a magic-link URL regardless of whether it
    /// carries a valid token. Used by `DeepLinkRouter` to claim the URL early.
    public static func isMagicLink(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return isMatch(components)
    }

    // MARK: - Private

    private static func isMatch(_ c: URLComponents) -> Bool {
        let scheme = c.scheme?.lowercased() ?? ""

        // bizarrecrm://auth/magic?token=…
        if scheme == customScheme {
            return c.host?.lowercased() == customHost && c.path == customPath
        }

        // https://app.bizarrecrm.com/auth/magic?token=…
        if scheme == "https" {
            return c.host?.lowercased() == universalHost && c.path == universalPath
        }

        return false
    }
}
