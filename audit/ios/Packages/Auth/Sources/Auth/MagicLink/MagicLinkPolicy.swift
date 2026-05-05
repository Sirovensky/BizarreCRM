import Foundation

// MARK: - §2.8 Magic link security policy

/// Enforces client-side magic-link security properties.
///
/// Server is the authority on link validity (one-time use, 15-min expiry, device binding).
/// This class handles the iOS-side checks the client can verify locally.
public struct MagicLinkPolicy: Sendable {

    // MARK: - Constants

    /// Magic links must originate from this domain (Universal Links).
    /// Custom-scheme `bizarrecrm://` links are also accepted for app-local routing
    /// but the token is always validated server-side.
    public static let pinnedDomain = "app.bizarrecrm.com"

    /// Maximum token age the client will attempt to exchange.
    /// Server enforces a matching (or shorter) window.
    public static let maxTokenLifetimeSeconds: TimeInterval = 15 * 60  // 15 min

    // MARK: - Tenant config

    /// Whether magic links are enabled for this tenant.
    /// Fetched from `GET /auth/session-policy` → `magicLinksEnabled`.
    /// Default: `true`.
    public var magicLinksEnabled: Bool

    // MARK: - Init

    public init(magicLinksEnabled: Bool = true) {
        self.magicLinksEnabled = magicLinksEnabled
    }

    // MARK: - Validation

    /// Returns `true` when the `url` is a well-formed magic-link URL from the
    /// pinned domain (or the custom app scheme), AND magic links are enabled.
    public func isValidMagicLink(_ url: URL) -> Bool {
        guard magicLinksEnabled else { return false }
        return MagicLinkURL.isMagicLink(url) && isFromPinnedDomain(url)
    }

    /// Returns `true` when the URL originates from `app.bizarrecrm.com` or the
    /// custom `bizarrecrm://` scheme (which is already validated by the OS to
    /// have been opened via Associated Domains or explicit scheme registration).
    public func isFromPinnedDomain(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        // Custom scheme — always internal; OS enforces the scheme registration.
        if components.scheme?.lowercased() == "bizarrecrm" { return true }
        // Universal Link — host must match the pinned domain exactly.
        return components.host?.lowercased() == Self.pinnedDomain
    }

    /// Returns `true` when the `issuedAt` token timestamp is within the max lifetime.
    ///
    /// If the server does not include `issuedAt` in the URL (it typically doesn't —
    /// the timestamp is in the server-side record), this check is skipped and
    /// the server's own expiry logic is authoritative.
    public func isWithinLifetime(issuedAt: Date) -> Bool {
        let age = Date().timeIntervalSince(issuedAt)
        return age >= 0 && age <= Self.maxTokenLifetimeSeconds
    }
}

// MARK: - APIClient extension for policy

import Networking

extension TenantSessionPolicy {
    /// Whether magic links are enabled for this tenant.
    /// Decoded from `GET /api/v1/auth/session-policy` response.
    public var magicLinksEnabled: Bool {
        // Default to enabled; the explicit disable flag comes from the tenant admin.
        // We use the existing Codable conformance; add `magicLinksEnabled` field if
        // the server starts returning it (server implementation tracked server-side).
        return true  // Conservative default; server disables via 403 on verify endpoint.
    }
}
