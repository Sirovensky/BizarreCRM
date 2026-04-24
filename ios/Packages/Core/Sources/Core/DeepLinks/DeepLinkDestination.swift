import Foundation

// MARK: - DeepLinkDestination

/// Typed enum representing every screen / action reachable via a deep link.
///
/// All cases are value-typed, `Sendable`, and `Equatable` so they can be
/// safely passed across actor boundaries and compared in unit tests.
///
/// - Note: This enum lives alongside `DeepLinkRoute` (the legacy parser output).
///   New code should prefer `DeepLinkDestination`; the validator and builder
///   work exclusively with this type.
public enum DeepLinkDestination: Sendable, Equatable, Hashable {

    // MARK: Dashboard
    case dashboard(tenantSlug: String)

    // MARK: Resources (require a tenant + record identifier)
    case ticket(tenantSlug: String, id: String)
    case customer(tenantSlug: String, id: String)
    case invoice(tenantSlug: String, id: String)
    case estimate(tenantSlug: String, id: String)
    case lead(tenantSlug: String, id: String)
    case appointment(tenantSlug: String, id: String)
    case inventory(tenantSlug: String, sku: String)
    case smsThread(tenantSlug: String, phone: String)
    case reports(tenantSlug: String, name: String)

    // MARK: POS
    case posRoot(tenantSlug: String)
    case posNewCart(tenantSlug: String)
    case posReturn(tenantSlug: String)

    // MARK: Settings
    case settings(tenantSlug: String, section: String?)
    case auditLogs(tenantSlug: String)

    // MARK: Utility
    case search(tenantSlug: String, query: String?)
    case notifications(tenantSlug: String)
    case timeclock(tenantSlug: String)

    // MARK: Auth
    case magicLink(tenantSlug: String?, token: String)
}

// MARK: - tenantSlug convenience

extension DeepLinkDestination {

    /// Returns the tenant slug when one is present, or `nil` for tenant-agnostic
    /// destinations such as a root magic-link invite.
    public var tenantSlug: String? {
        switch self {
        case .dashboard(let slug),
             .ticket(let slug, _),
             .customer(let slug, _),
             .invoice(let slug, _),
             .estimate(let slug, _),
             .lead(let slug, _),
             .appointment(let slug, _),
             .inventory(let slug, _),
             .smsThread(let slug, _),
             .reports(let slug, _),
             .posRoot(let slug),
             .posNewCart(let slug),
             .posReturn(let slug),
             .settings(let slug, _),
             .auditLogs(let slug),
             .search(let slug, _),
             .notifications(let slug),
             .timeclock(let slug):
            return slug
        case .magicLink(let slug, _):
            return slug
        }
    }
}
