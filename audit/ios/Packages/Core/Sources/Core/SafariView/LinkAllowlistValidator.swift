import Foundation

// MARK: - LinkAllowlistValidator

/// Guards external URL opens against open-redirect and phishing attacks.
///
/// Only URLs whose host is in the configured tenant domain or the Apple
/// privacy-policy domain are considered safe to open in-app.
///
/// ## Threat model
/// - Prevents an attacker from crafting a link that causes the app to
///   open an arbitrary external website in `SFSafariViewController`.
/// - Tenant domain is dynamic (self-hosted installs vary), so it is
///   supplied at runtime rather than compiled-in.
///
/// ## Usage
/// ```swift
/// let validator = LinkAllowlistValidator(tenantHost: "app.acme.bizarrecrm.com")
/// switch validator.validate(url) {
/// case .allowed:  presentSafari(url)
/// case .blocked(let reason): logger.warning("Blocked: \(reason)")
/// }
/// ```
///
/// Thread-safe: all stored state is immutable after init.
public struct LinkAllowlistValidator: Sendable {

    // MARK: - Result

    /// The outcome of a link-allowlist check.
    public enum Result: Sendable, Equatable {
        /// The URL is safe to open in-app.
        case allowed
        /// The URL must not be opened in-app.
        case blocked(reason: String)

        /// Convenience accessor.
        public var isAllowed: Bool {
            if case .allowed = self { return true }
            return false
        }
    }

    // MARK: - Fixed Allowlist

    /// Apple's privacy-policy domain, always permitted.
    public static let applePrivacyHost = "www.apple.com"

    /// The canonical BizarreCRM universal-link host, always permitted.
    public static let canonicalAppHost = DeepLinkURLParser.universalLinkHost

    // MARK: - Stored Properties

    /// The tenant's dynamic hostname (e.g. `app.bizarrecrm.com` or a
    /// self-hosted equivalent).  Matched with exact-host or suffix rules.
    public let tenantHost: String

    /// Additional hosts explicitly allowed by the caller (e.g. CDN, docs).
    public let extraAllowedHosts: Set<String>

    // MARK: - Init

    /// - Parameters:
    ///   - tenantHost:         The tenant server's hostname.
    ///   - extraAllowedHosts:  Any additional hosts to allow (defaults to empty).
    public init(
        tenantHost: String,
        extraAllowedHosts: Set<String> = []
    ) {
        self.tenantHost = tenantHost.lowercased()
        self.extraAllowedHosts = Set(extraAllowedHosts.map { $0.lowercased() })
    }

    // MARK: - Public API

    /// Validate `url` against the configured allowlist.
    ///
    /// Checks (in order):
    /// 1. URL must use `https` (never `http`, never custom schemes).
    /// 2. URL must have a non-empty host.
    /// 3. Host must match one of: tenant host, canonical app host, Apple privacy host,
    ///    or any extra allowed host.
    public func validate(_ url: URL) -> Result {
        // 1. Scheme must be https
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else {
            return .blocked(reason: "Only HTTPS links may be opened in-app")
        }

        // 2. Host must be present
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return .blocked(reason: "URL has no host")
        }

        // 3. Host allowlist check
        var allowedHosts: Set<String> = [
            tenantHost,
            Self.canonicalAppHost,
            Self.applePrivacyHost
        ]
        allowedHosts.formUnion(extraAllowedHosts)

        guard allowedHosts.contains(host) else {
            return .blocked(reason: "Host '\(host)' is not in the tenant allowlist")
        }

        return .allowed
    }
}
