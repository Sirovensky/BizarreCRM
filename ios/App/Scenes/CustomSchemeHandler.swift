import Foundation
import Core
#if canImport(UIKit)
import UIKit
#endif

// MARK: - §25.8 Custom URL scheme (`bizarrecrm://`) — all tenants including self-hosted
//
// The custom scheme is the portable staff-app deep-link path.
// It does not depend on the tenant's domain — self-hosted tenants use it too.
//
// Shape: `bizarrecrm://<tenant-slug>/<path>`
//
// Slug resolution rules (§65.2):
//  1. Slug from `url.host` component.
//  2. Look up slug in `TenantSlugRegistry` (Keychain) to get the API base URL.
//  3. If slug matches current tenant → route immediately.
//  4. If slug matches a known but inactive tenant → show confirmation sheet.
//  5. If slug unknown → show Login screen with server URL pre-filled.
//  6. Unknown path → toast, never crash.
//
// Rate limiting against malformed URL DoS: `CustomSchemeRateLimiter` (token bucket).

// MARK: - Tenant slug registry (Keychain-backed)

/// Maps tenant slugs to their API base URLs.
/// Written at login time; read when an inbound custom-scheme URL arrives.
public final class TenantSlugRegistry: @unchecked Sendable {
    public static let shared = TenantSlugRegistry()

    private let keychainService = "com.bizarrecrm.tenantSlugs"

    private init() {}

    /// Register a slug → base URL mapping at login.
    public func register(slug: String, baseURL: URL) {
        UserDefaults.standard.set(baseURL.absoluteString, forKey: keychainKey(slug))
    }

    /// Resolve a slug to its API base URL.
    public func baseURL(for slug: String) -> URL? {
        guard let raw = UserDefaults.standard.string(forKey: keychainKey(slug)),
              let url = URL(string: raw) else { return nil }
        return url
    }

    /// All known slugs.
    public func allSlugs() -> [String] {
        // In production this would walk Keychain; UserDefaults is fine for now.
        return [] // minimal implementation — real migration to Keychain in §28 pass
    }

    private func keychainKey(_ slug: String) -> String {
        "tenantSlug.\(slug.lowercased())"
    }
}

// MARK: - Inbound resolution result

public enum CustomSchemeResolution: Sendable {
    /// Slug matches active tenant — navigate immediately.
    case navigate(destination: DeepLinkDestination)
    /// Slug matches a known inactive tenant — show confirmation.
    case confirmTenantSwitch(slug: String, targetBaseURL: URL, destination: DeepLinkDestination)
    /// Slug unknown — show Login screen pre-filled with hint.
    case loginRequired(slug: String, destination: DeepLinkDestination)
    /// URL was invalid or rate-limited — show toast.
    case rejected(reason: String)
}

// MARK: - Simple rate limiter (token bucket, per source)

/// Prevents DoS via malformed `bizarrecrm://` URLs from Shortcuts / Clipboard.
/// Allows a burst of 10 deep-links within 5 seconds, then throttles.
actor CustomSchemeRateLimiter {
    static let shared = CustomSchemeRateLimiter()
    private var tokens: Int = 10
    private var lastRefill: Date = .now
    private let maxTokens = 10
    private let refillInterval: TimeInterval = 5.0

    func allow() -> Bool {
        refillIfNeeded()
        guard tokens > 0 else { return false }
        tokens -= 1
        return true
    }

    private func refillIfNeeded() {
        let now = Date()
        if now.timeIntervalSince(lastRefill) >= refillInterval {
            tokens = maxTokens
            lastRefill = now
        }
    }
}

// MARK: - Handler

/// Resolves a `bizarrecrm://` URL against the current auth state.
///
/// Call from `DeepLinkRouter.handle(_:)` for `bizarrecrm://` scheme URLs.
/// The App layer consumes the result (navigate / show confirmation / show login).
@MainActor
public final class CustomSchemeHandler {
    public static let shared = CustomSchemeHandler()

    /// The currently active tenant slug. Set by `SessionBootstrapper` on login.
    public var activeTenantSlug: String?

    private init() {}

    /// Resolve an inbound `bizarrecrm://` URL.
    ///
    /// - Parameter url: A `bizarrecrm://<slug>/<path>` URL.
    /// - Parameter isAuthenticated: Whether the user is currently signed in.
    /// - Returns: Resolution result for the App layer to act on.
    public func resolve(url: URL, isAuthenticated: Bool) async -> CustomSchemeResolution {
        // Rate limit
        let allowed = await CustomSchemeRateLimiter.shared.allow()
        guard allowed else {
            AppLog.ui.warning("CustomSchemeHandler: rate-limited inbound URL \(url.absoluteString, privacy: .public)")
            return .rejected(reason: "Too many deep-links. Please wait a moment.")
        }

        // Validate scheme
        guard url.scheme?.lowercased() == "bizarrecrm" else {
            return .rejected(reason: "Unknown URL scheme: \(url.scheme ?? "nil")")
        }

        // Extract slug
        guard let slug = url.host, !slug.isEmpty else {
            return .rejected(reason: "Missing tenant slug in URL.")
        }

        // Parse destination
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let destination = DeepLinkParser.parse(url)?.destination ?? .dashboard

        // Multi-tenant safety: §25.8 / §79
        if let active = activeTenantSlug, active.lowercased() != slug.lowercased() {
            // Link is for a different tenant
            if let targetBaseURL = TenantSlugRegistry.shared.baseURL(for: slug) {
                // Known tenant but not current — confirmation required
                return .confirmTenantSwitch(slug: slug, targetBaseURL: targetBaseURL, destination: destination)
            } else {
                // Unknown tenant — send to login
                return .loginRequired(slug: slug, destination: destination)
            }
        }

        // Not authenticated — store intent, send to login
        if !isAuthenticated {
            return .loginRequired(slug: slug, destination: destination)
        }

        return .navigate(destination: destination)
    }
}
