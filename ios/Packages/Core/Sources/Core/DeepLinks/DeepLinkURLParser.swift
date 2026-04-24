import Foundation

// MARK: - DeepLinkURLParser

/// Parses a raw `URL` into a `DeepLinkDestination`.
///
/// Supports two URL forms:
///
/// 1. **Custom scheme** — `bizarrecrm://<tenantSlug>/<resource>[/<id>][?params]`
/// 2. **Universal link** — `https://app.bizarrecrm.com/<tenantSlug>/<resource>[/<id>][?params]`
///
/// Returns `nil` for any URL that cannot be mapped to a known destination.
/// Never throws; malformed URLs always yield `nil`.
///
/// Thread-safe: all state is static / stack-local; the type holds no stored properties.
public enum DeepLinkURLParser {

    // MARK: - Constants

    public static let customScheme        = "bizarrecrm"
    public static let universalLinkHost   = "app.bizarrecrm.com"
    static let publicPathPrefix           = "/public"

    // MARK: - Public API

    /// Parse `url` into a `DeepLinkDestination`, returning `nil` if the URL is
    /// not a recognised deep-link.
    public static func parse(_ url: URL) -> DeepLinkDestination? {
        guard let scheme = url.scheme?.lowercased() else { return nil }

        switch scheme {
        case customScheme:
            return parseCustomScheme(url)
        case "https", "http":
            return parseUniversalLink(url)
        default:
            return nil
        }
    }

    // MARK: - Custom-scheme parser

    /// Parses `bizarrecrm://<slug>/<resource>[/<id>][?params]`
    private static func parseCustomScheme(_ url: URL) -> DeepLinkDestination? {
        guard
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let slug = url.host, !slug.isEmpty
        else { return nil }

        let parts = pathParts(from: url)
        return route(
            slug: slug,
            parts: parts,
            queryItems: comps.queryItems
        )
    }

    // MARK: - Universal-link parser

    /// Parses `https://app.bizarrecrm.com/<slug>/<resource>[/<id>][?params]`
    private static func parseUniversalLink(_ url: URL) -> DeepLinkDestination? {
        guard
            let host = url.host?.lowercased(),
            host == universalLinkHost
        else { return nil }

        // /public/* is served to external (non-app) users; don't intercept.
        let rawPath = url.path
        if rawPath == publicPathPrefix
            || rawPath.hasPrefix(publicPathPrefix + "/") { return nil }

        let parts = pathParts(from: url)
        guard let slug = parts.first, !slug.isEmpty else { return nil }

        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        // Drop the leading slug segment before routing.
        let resourceParts = Array(parts.dropFirst())
        return route(
            slug: slug,
            parts: resourceParts,
            queryItems: comps.queryItems
        )
    }

    // MARK: - Shared route dispatcher

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func route(
        slug: String,
        parts: [String],
        queryItems: [URLQueryItem]?
    ) -> DeepLinkDestination? {

        func q(_ name: String) -> String? {
            queryItems?.first { $0.name == name }?.value
        }

        let resource = parts.first?.lowercased()
        let idOrSub  = parts.count > 1 ? parts[1] : nil
        let subpath  = parts.count > 2 ? parts[2] : nil

        switch resource {

        // MARK: Dashboard
        case "dashboard", nil:
            return .dashboard(tenantSlug: slug)

        // MARK: Tickets
        case "tickets":
            guard let id = idOrSub, !id.isEmpty else { return nil }
            return .ticket(tenantSlug: slug, id: id)

        // MARK: Customers
        case "customers":
            guard let id = idOrSub, !id.isEmpty else { return nil }
            return .customer(tenantSlug: slug, id: id)

        // MARK: Invoices
        case "invoices":
            guard let id = idOrSub, !id.isEmpty else { return nil }
            return .invoice(tenantSlug: slug, id: id)

        // MARK: Estimates
        case "estimates":
            guard let id = idOrSub, !id.isEmpty else { return nil }
            return .estimate(tenantSlug: slug, id: id)

        // MARK: Leads
        case "leads":
            guard let id = idOrSub, !id.isEmpty else { return nil }
            return .lead(tenantSlug: slug, id: id)

        // MARK: Appointments
        case "appointments":
            guard let id = idOrSub, !id.isEmpty else { return nil }
            return .appointment(tenantSlug: slug, id: id)

        // MARK: Inventory
        case "inventory":
            guard let sku = idOrSub, !sku.isEmpty else { return nil }
            return .inventory(tenantSlug: slug, sku: sku)

        // MARK: SMS
        case "sms":
            guard let phone = idOrSub, !phone.isEmpty else { return nil }
            return .smsThread(tenantSlug: slug, phone: phone)

        // MARK: POS
        case "pos":
            switch idOrSub?.lowercased() {
            case "new":
                return .posNewCart(tenantSlug: slug)
            case "sale":
                return subpath?.lowercased() == "new"
                    ? .posNewCart(tenantSlug: slug)
                    : .posRoot(tenantSlug: slug)
            case "return":
                return .posReturn(tenantSlug: slug)
            case nil:
                return .posRoot(tenantSlug: slug)
            default:
                return .posRoot(tenantSlug: slug)
            }

        // MARK: Settings
        case "settings":
            switch idOrSub?.lowercased() {
            case "audit":
                return .auditLogs(tenantSlug: slug)
            case let section:
                return .settings(tenantSlug: slug, section: section)
            }

        // MARK: Search
        case "search":
            return .search(tenantSlug: slug, query: q("q"))

        // MARK: Notifications
        case "notifications":
            return .notifications(tenantSlug: slug)

        // MARK: Reports
        case "reports":
            guard let name = idOrSub, !name.isEmpty else { return nil }
            return .reports(tenantSlug: slug, name: name)

        // MARK: Timeclock
        case "timeclock":
            return .timeclock(tenantSlug: slug)

        // MARK: Auth
        case "auth":
            switch idOrSub?.lowercased() {
            case "magic":
                guard let token = q("token"), !token.isEmpty else { return nil }
                return .magicLink(tenantSlug: slug, token: token)
            default:
                return nil
            }

        default:
            return nil
        }
    }

    // MARK: - Helpers

    private static func pathParts(from url: URL) -> [String] {
        url.pathComponents.filter { $0 != "/" }
    }
}
