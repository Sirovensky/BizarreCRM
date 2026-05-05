import Foundation

// MARK: - DeepLinkBuilder

/// Builds a canonical `URL` from a `DeepLinkDestination`.
///
/// Two forms are supported via `Form`:
/// - `.customScheme` — produces `bizarrecrm://<slug>/…`
/// - `.universalLink` — produces `https://app.bizarrecrm.com/<slug>/…`
///
/// Both forms are round-trip compatible with `DeepLinkURLParser`.
/// Returns `nil` only when a `URLComponents` assembly error occurs (should
/// never happen for well-formed destinations).
///
/// Thread-safe: stateless enum.
public enum DeepLinkBuilder {

    // MARK: - Form

    /// Selects the URL representation to produce.
    public enum Form {
        /// `bizarrecrm://<slug>/…`
        case customScheme
        /// `https://app.bizarrecrm.com/<slug>/…`
        case universalLink
    }

    // MARK: - Public API

    /// Build a URL for `destination` in the given `form`.
    ///
    /// - Returns: A fully-formed `URL`, or `nil` if assembly fails.
    public static func build(
        _ destination: DeepLinkDestination,
        form: Form = .customScheme
    ) -> URL? {
        var comps = URLComponents()

        switch form {
        case .customScheme:
            comps.scheme = DeepLinkURLParser.customScheme
        case .universalLink:
            comps.scheme = "https"
            comps.host   = DeepLinkURLParser.universalLinkHost
        }

        let (slug, resourcePath, queryItems) = components(for: destination)

        switch form {
        case .customScheme:
            comps.host = slug
            comps.path = resourcePath.isEmpty ? "" : "/" + resourcePath
        case .universalLink:
            let prefix = slug.map { $0 + "/" } ?? ""
            comps.path = "/" + prefix + resourcePath
        }

        if let items = queryItems, !items.isEmpty {
            comps.queryItems = items
        }

        return comps.url
    }

    // MARK: - Decompose destination into (slug, path, queryItems)

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func components(
        for destination: DeepLinkDestination
    ) -> (slug: String?, path: String, queryItems: [URLQueryItem]?) {

        switch destination {

        case .dashboard(let slug):
            return (slug, "dashboard", nil)

        case .ticket(let slug, let id):
            return (slug, "tickets/\(pct(id))", nil)

        case .customer(let slug, let id):
            return (slug, "customers/\(pct(id))", nil)

        case .invoice(let slug, let id):
            return (slug, "invoices/\(pct(id))", nil)

        case .estimate(let slug, let id):
            return (slug, "estimates/\(pct(id))", nil)

        case .lead(let slug, let id):
            return (slug, "leads/\(pct(id))", nil)

        case .appointment(let slug, let id):
            return (slug, "appointments/\(pct(id))", nil)

        case .inventory(let slug, let sku):
            return (slug, "inventory/\(pct(sku))", nil)

        case .smsThread(let slug, let phone):
            return (slug, "sms/\(pct(phone))", nil)

        case .reports(let slug, let name):
            return (slug, "reports/\(pct(name))", nil)

        case .posRoot(let slug):
            return (slug, "pos", nil)

        case .posNewCart(let slug):
            return (slug, "pos/new", nil)

        case .posReturn(let slug):
            return (slug, "pos/return", nil)

        case .settings(let slug, let section):
            if let section = section {
                return (slug, "settings/\(pct(section))", nil)
            }
            return (slug, "settings", nil)

        case .auditLogs(let slug):
            return (slug, "settings/audit", nil)

        case .search(let slug, let query):
            let items: [URLQueryItem]? = query.map {
                [URLQueryItem(name: "q", value: $0)]
            }
            return (slug, "search", items)

        case .notifications(let slug):
            return (slug, "notifications", nil)

        case .timeclock(let slug):
            return (slug, "timeclock", nil)

        case .magicLink(let slug, let token):
            let items = [URLQueryItem(name: "token", value: token)]
            return (slug, "auth/magic", items)

        case .resetPassword(let token):
            // Slug-free: `https://app.bizarrecrm.com/reset-password/<token>` (§2.8)
            return (nil, "reset-password/\(pct(token))", nil)

        case .setupInvite(let token):
            // Slug-free: `https://app.bizarrecrm.com/setup/<token>` (§2.7)
            return (nil, "setup/\(pct(token))", nil)
        }
    }

    // MARK: - Percent-encoding helper

    /// Percent-encodes a path segment value, preserving alphanumerics and `-_~.`.
    private static func pct(_ value: String) -> String {
        value.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? value
    }
}
