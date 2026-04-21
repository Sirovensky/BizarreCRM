import Foundation

/// A tenant (shop / organisation) the authenticated user belongs to.
///
/// One user can belong to multiple tenants (franchise owners, consultants,
/// contractors). `TenantStore` holds the currently-active one and the full
/// cached list.
public struct Tenant: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    /// Short slug used in URL paths and deep-links.
    public let slug: String
    /// Per-tenant base URL. `nil` means the tenant shares the default server.
    public let baseURL: URL?
    /// The authenticated user's role within this tenant.
    public let role: String
    /// Optional logo shown in the tenant picker rows.
    public let logoUrl: URL?
    /// When the user last accessed this tenant (for sorting + relative timestamps).
    public let lastAccessedAt: Date?

    public init(
        id: String,
        name: String,
        slug: String,
        baseURL: URL? = nil,
        role: String,
        logoUrl: URL? = nil,
        lastAccessedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.baseURL = baseURL
        self.role = role
        self.logoUrl = logoUrl
        self.lastAccessedAt = lastAccessedAt
    }
}
