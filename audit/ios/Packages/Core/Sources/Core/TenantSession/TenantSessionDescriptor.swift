import Foundation

// §79 Multi-Tenant Session management

/// Immutable description of a single tenant the user can sign into.
///
/// The struct is `Identifiable` (by `id`), `Hashable`, `Codable`, and `Sendable`
/// so it can travel safely across actor boundaries and survive Keychain round-trips.
public struct TenantSessionDescriptor: Identifiable, Hashable, Codable, Sendable {

    // MARK: — Properties

    /// Stable, server-assigned tenant identifier (e.g. UUID string or slug).
    public let id: String

    /// Human-readable name shown in tenant-picker UI.
    public let displayName: String

    /// Base URL for this tenant's API.  Every network call for this tenant is
    /// rooted here.  Must be a valid `https://` URL in production.
    public let baseURL: URL

    /// Wall-clock time when the user last activated this tenant.
    /// Used to sort the tenant roster "most-recent first."
    public let lastUsedAt: Date

    // MARK: — Init

    public init(
        id: String,
        displayName: String,
        baseURL: URL,
        lastUsedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.lastUsedAt = lastUsedAt
    }

    // MARK: — Derived helpers

    /// Returns a copy with `lastUsedAt` updated to the given date (immutable update).
    public func touchingLastUsed(at date: Date = Date()) -> TenantSessionDescriptor {
        TenantSessionDescriptor(
            id: id,
            displayName: displayName,
            baseURL: baseURL,
            lastUsedAt: date
        )
    }
}
