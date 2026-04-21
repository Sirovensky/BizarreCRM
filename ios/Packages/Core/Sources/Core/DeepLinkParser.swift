import Foundation

// MARK: - DeepLinkRoute

/// All routes the app can navigate to via a deep link.
///
/// The enum is pure-value, `Sendable`, and `Equatable` so it can be
/// freely passed across actor boundaries and compared in tests.
public enum DeepLinkRoute: Sendable, Equatable {
    // Resources with tenant context
    case ticket(tenantSlug: String, id: String)
    case customer(tenantSlug: String, id: String)
    case invoice(tenantSlug: String, id: String)
    case estimate(tenantSlug: String, id: String)
    case lead(tenantSlug: String, id: String)
    case appointment(tenantSlug: String, id: String)
    case inventory(tenantSlug: String, sku: String)
    case smsThread(tenantSlug: String, threadID: String)
    case reports(tenantSlug: String, name: String)
    case notifications(tenantSlug: String)
    case search(tenantSlug: String, query: String?)
    case timeclock(tenantSlug: String)

    // POS
    case posNewCart(tenantSlug: String)
    case posRoot(tenantSlug: String)
    case posReturn(tenantSlug: String)

    // Settings
    case auditLogs(tenantSlug: String)
    case settings(tenantSlug: String, section: String?)

    // Dashboard
    case dashboard(tenantSlug: String)

    // Auth
    case magicLink(tenantSlug: String?, token: String)

    // Non-app
    case safariExternal(URL)
    case unknown(URL)
}

// MARK: - DeepLinkParser

/// Pure, UIKit-free parser.  Lives in the Core package so it can be
/// exercised with `swift test` without a simulator.
///
/// `DeepLinkRouter` (App target) is the thin `@MainActor` wrapper that
/// holds `@Published var pending` and dispatches this parser.
public enum DeepLinkParser {

    // MARK: Constants

    static let customScheme = "bizarrecrm"
    static let universalLinkHost = "app.bizarrecrm.com"
    static let publicPathPrefix = "/public/"

    // MARK: Public API

    /// Parse any URL into a `DeepLinkRoute`.
    ///
    /// Rules (in priority order):
    /// 1. `bizarrecrm://` — custom scheme; first host component is slug.
    /// 2. `https://app.bizarrecrm.com/public/*` — customer-facing; open externally.
    /// 3. `https://app.bizarrecrm.com/*` — universal link; strip leading `/` and treat
    ///    first path segment as slug.
    /// 4. Anything else → `.safariExternal(url)`.
    public static func parse(_ url: URL) -> DeepLinkRoute {
        guard let scheme = url.scheme?.lowercased() else {
            return .unknown(url)
        }

        switch scheme {
        case customScheme:
            return parseCustomScheme(url)
        case "https", "http":
            return parseHTTP(url)
        default:
            return .safariExternal(url)
        }
    }

    // MARK: - Custom scheme parser

    /// Parses `bizarrecrm://<slug>/<resource>[/<id>][?params]`
    private static func parseCustomScheme(_ url: URL) -> DeepLinkRoute {
        // URLComponents gives us reliable query-item access.
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .unknown(url)
        }

        // `url.host` is the first path segment after `//` — i.e. the tenant slug.
        guard let slug = url.host, !slug.isEmpty else {
            return .unknown(url)
        }

        // Path components without the leading "/".
        let parts = url.pathComponents.filter { $0 != "/" }
        let resource = parts.first?.lowercased()
        let idOrSub  = parts.count > 1 ? parts[1] : nil
        let subpath  = parts.count > 2 ? parts[2] : nil

        return route(
            slug: slug,
            resource: resource,
            idOrSub: idOrSub,
            subpath: subpath,
            queryItems: comps.queryItems,
            originalURL: url
        )
    }

    // MARK: - HTTP / Universal link parser

    private static func parseHTTP(_ url: URL) -> DeepLinkRoute {
        guard
            let host = url.host?.lowercased(),
            host == universalLinkHost
        else {
            // Unknown https host — open externally.
            return .safariExternal(url)
        }

        let path = url.path
        if path.hasPrefix(publicPathPrefix) || path == "/public" {
            return .safariExternal(url)
        }

        // Strip leading "/" from path components.
        let parts = url.pathComponents.filter { $0 != "/" }

        // For universal links the first segment is expected to be the slug,
        // same structure as the custom scheme.
        guard let slug = parts.first, !slug.isEmpty else {
            return .unknown(url)
        }

        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .unknown(url)
        }

        let resource = parts.count > 1 ? parts[1].lowercased() : nil
        let idOrSub  = parts.count > 2 ? parts[2] : nil
        let subpath  = parts.count > 3 ? parts[3] : nil

        return route(
            slug: slug,
            resource: resource,
            idOrSub: idOrSub,
            subpath: subpath,
            queryItems: comps.queryItems,
            originalURL: url
        )
    }

    // MARK: - Shared route dispatcher

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func route(
        slug: String,
        resource: String?,
        idOrSub: String?,
        subpath: String?,
        queryItems: [URLQueryItem]?,
        originalURL: URL
    ) -> DeepLinkRoute {

        func queryValue(_ name: String) -> String? {
            queryItems?.first { $0.name == name }?.value
        }

        switch resource {

        // MARK: Auth
        case "auth":
            switch idOrSub?.lowercased() {
            case "magic":
                guard let token = queryValue("token"), !token.isEmpty else {
                    return .unknown(originalURL)
                }
                return .magicLink(tenantSlug: slug, token: token)
            default:
                return .unknown(originalURL)
            }

        // MARK: Dashboard
        case "dashboard", nil:
            return .dashboard(tenantSlug: slug)

        // MARK: Tickets
        case "tickets":
            guard let id = idOrSub, !id.isEmpty else {
                return .unknown(originalURL)
            }
            return .ticket(tenantSlug: slug, id: id)

        // MARK: Customers
        case "customers":
            guard let id = idOrSub, !id.isEmpty else {
                return .unknown(originalURL)
            }
            return .customer(tenantSlug: slug, id: id)

        // MARK: Invoices
        case "invoices":
            guard let id = idOrSub, !id.isEmpty else {
                return .unknown(originalURL)
            }
            return .invoice(tenantSlug: slug, id: id)

        // MARK: Estimates
        case "estimates":
            guard let id = idOrSub, !id.isEmpty else {
                return .unknown(originalURL)
            }
            return .estimate(tenantSlug: slug, id: id)

        // MARK: Leads
        case "leads":
            guard let id = idOrSub, !id.isEmpty else {
                return .unknown(originalURL)
            }
            return .lead(tenantSlug: slug, id: id)

        // MARK: Appointments
        case "appointments":
            guard let id = idOrSub, !id.isEmpty else {
                return .unknown(originalURL)
            }
            return .appointment(tenantSlug: slug, id: id)

        // MARK: Inventory
        case "inventory":
            guard let sku = idOrSub, !sku.isEmpty else {
                return .unknown(originalURL)
            }
            return .inventory(tenantSlug: slug, sku: sku)

        // MARK: SMS
        case "sms":
            guard let threadID = idOrSub, !threadID.isEmpty else {
                return .unknown(originalURL)
            }
            return .smsThread(tenantSlug: slug, threadID: threadID)

        // MARK: POS
        case "pos":
            switch idOrSub?.lowercased() {
            case "new":
                return .posNewCart(tenantSlug: slug)
            case "sale":
                if subpath?.lowercased() == "new" {
                    return .posNewCart(tenantSlug: slug)
                }
                return .posRoot(tenantSlug: slug)
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
            let q = queryValue("q")
            return .search(tenantSlug: slug, query: q)

        // MARK: Notifications
        case "notifications":
            return .notifications(tenantSlug: slug)

        // MARK: Reports
        case "reports":
            guard let name = idOrSub, !name.isEmpty else {
                return .unknown(originalURL)
            }
            return .reports(tenantSlug: slug, name: name)

        // MARK: Timeclock
        case "timeclock":
            return .timeclock(tenantSlug: slug)

        default:
            return .unknown(originalURL)
        }
    }
}
