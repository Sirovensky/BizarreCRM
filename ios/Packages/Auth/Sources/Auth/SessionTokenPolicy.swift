import Foundation
import Core

// MARK: - §28.14 Access-token / refresh-token lifetime policy
//
// Canonical TTL constants for the iOS session layer. The server
// declares these in `/auth/me`'s `session_policy` block when present,
// but we keep deterministic client-side defaults so the app behaves
// identically on tenants whose servers haven't been upgraded yet.
//
// **Policy (§28.14):**
// - Access token: 1 hour.
// - Refresh token: 30 days, **rotating** — every refresh issues a new
//   refresh token and invalidates the previous one.  This is what
//   §28 spec calls "rotating refresh-token rotation".
//
// `AuthSessionRefresher` (existing, in Networking) consults this struct
// for both the proactive-refresh window and the absolute expiry guard.

/// Server-supplied or default token lifetime + rotation rules.  Pure
/// value type; safe to pass across actors.
public struct SessionTokenPolicy: Sendable, Equatable, Codable {

    // MARK: - Canonical defaults (§28.14)

    /// Default access-token lifetime — **1 hour**.
    public static let defaultAccessTokenLifetime: TimeInterval = 60 * 60

    /// Default refresh-token lifetime — **30 days**.
    public static let defaultRefreshTokenLifetime: TimeInterval = 30 * 24 * 60 * 60

    /// Refresh proactively when ≤ this many seconds remain on the access
    /// token.  Five minutes leaves room for clock skew + network latency
    /// without burning refresh tokens unnecessarily often.
    public static let defaultProactiveRefreshLeadTime: TimeInterval = 5 * 60

    // MARK: - Properties

    /// Seconds an access token is valid after issuance.
    public let accessTokenLifetime: TimeInterval

    /// Seconds a refresh token is valid after issuance.
    public let refreshTokenLifetime: TimeInterval

    /// Seconds-before-expiry at which we initiate a proactive refresh.
    public let proactiveRefreshLeadTime: TimeInterval

    /// `true` when refresh tokens rotate on every use (§28.14).  Always
    /// `true` for production; left as a flag so dev/test fixtures can
    /// disable rotation for replay scenarios.
    public let rotatesOnRefresh: Bool

    // MARK: - Init

    public init(
        accessTokenLifetime: TimeInterval = SessionTokenPolicy.defaultAccessTokenLifetime,
        refreshTokenLifetime: TimeInterval = SessionTokenPolicy.defaultRefreshTokenLifetime,
        proactiveRefreshLeadTime: TimeInterval = SessionTokenPolicy.defaultProactiveRefreshLeadTime,
        rotatesOnRefresh: Bool = true
    ) {
        self.accessTokenLifetime = accessTokenLifetime
        self.refreshTokenLifetime = refreshTokenLifetime
        self.proactiveRefreshLeadTime = proactiveRefreshLeadTime
        self.rotatesOnRefresh = rotatesOnRefresh
    }

    /// Canonical §28.14 default policy.
    public static let `default` = SessionTokenPolicy()

    // MARK: - Helpers

    /// Date at which an access token issued at `issuedAt` expires.
    public func accessTokenExpiry(issuedAt: Date) -> Date {
        issuedAt.addingTimeInterval(accessTokenLifetime)
    }

    /// Date at which a refresh token issued at `issuedAt` expires.
    public func refreshTokenExpiry(issuedAt: Date) -> Date {
        issuedAt.addingTimeInterval(refreshTokenLifetime)
    }

    /// `true` when an access token issued at `issuedAt` is within the
    /// proactive-refresh window (or already expired) at `now`.
    public func shouldProactivelyRefresh(issuedAt: Date, now: Date = Date()) -> Bool {
        let expiry = accessTokenExpiry(issuedAt: issuedAt)
        return now.addingTimeInterval(proactiveRefreshLeadTime) >= expiry
    }

    /// `true` when a refresh token issued at `issuedAt` has expired —
    /// the user must re-authenticate from scratch.
    public func isRefreshTokenExpired(issuedAt: Date, now: Date = Date()) -> Bool {
        now >= refreshTokenExpiry(issuedAt: issuedAt)
    }
}

// MARK: - Server override

/// Server-supplied policy block, decoded from `/auth/me` when present.
/// Any field omitted falls back to the canonical default.  Server
/// values are clamped on receipt so a misconfigured tenant cannot
/// extend access-token lifetime past 24h or refresh past 90d.
public struct SessionTokenPolicyOverride: Sendable, Equatable, Codable {

    public let accessTokenSeconds: Int?
    public let refreshTokenSeconds: Int?
    public let rotatesOnRefresh: Bool?

    public init(
        accessTokenSeconds: Int? = nil,
        refreshTokenSeconds: Int? = nil,
        rotatesOnRefresh: Bool? = nil
    ) {
        self.accessTokenSeconds = accessTokenSeconds
        self.refreshTokenSeconds = refreshTokenSeconds
        self.rotatesOnRefresh = rotatesOnRefresh
    }

    /// Returns a fully-resolved `SessionTokenPolicy`, applying clamps:
    /// - Access token: 5 min ≤ x ≤ 24 h.
    /// - Refresh token: 1 h ≤ x ≤ 90 d.
    public func resolved() -> SessionTokenPolicy {
        let access: TimeInterval = {
            guard let s = accessTokenSeconds else {
                return SessionTokenPolicy.defaultAccessTokenLifetime
            }
            return TimeInterval(min(max(s, 5 * 60), 24 * 60 * 60))
        }()
        let refresh: TimeInterval = {
            guard let s = refreshTokenSeconds else {
                return SessionTokenPolicy.defaultRefreshTokenLifetime
            }
            return TimeInterval(min(max(s, 60 * 60), 90 * 24 * 60 * 60))
        }()
        return SessionTokenPolicy(
            accessTokenLifetime: access,
            refreshTokenLifetime: refresh,
            proactiveRefreshLeadTime: SessionTokenPolicy.defaultProactiveRefreshLeadTime,
            rotatesOnRefresh: rotatesOnRefresh ?? true
        )
    }
}
