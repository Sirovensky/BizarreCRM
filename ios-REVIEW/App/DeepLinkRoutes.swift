import Foundation

// MARK: - §65 Deep-link / URL scheme reference
//
// Three URL concepts (see ios/ActionPlan.md §65.0):
//
//  A. Tenant API base URL  — `https://app.bizarrecrm.com` / `https://10.0.1.12`
//     Used by APIClient for network calls. Set at login. Entirely independent of B and C.
//
//  B. Universal Links (HTTPS) — cloud-hosted tenants only.
//     Example: `https://app.bizarrecrm.com/tickets/123`
//     iOS validates AASA on `app.bizarrecrm.com` + `*.bizarrecrm.com` (entitlement).
//     NOT available for self-hosted tenants whose domain is not in the signed entitlement.
//
//  C. Custom scheme (local iOS routing) — every tenant incl. self-hosted.
//     Example: `bizarrecrm://acme-repair/tickets/123`
//     No network, no DNS. Registered in Info.plist CFBundleURLSchemes.
//     First path component = tenant slug (from /auth/me → cached in Keychain).
//
// This file defines:
//   1. `DeepLinkScheme` — constants for the custom-scheme router.
//   2. `DeepLinkPath`   — builder for `bizarrecrm://<slug>/<path>` URLs.
//   3. `DeepLinkParser` — decodes an inbound URL into a `DeepLinkDestination`.
//
// IMPORTANT: This file is additive — feature modules add their routes here via
// DeepLinkRouter.register(...) from their module init; do not edit another
// module's registration block.

// MARK: - Constants

public enum DeepLinkScheme {
    public static let scheme = "bizarrecrm"
}

// MARK: - Route paths (§65.2 table)

public enum DeepLinkPath {
    // Dashboard
    public static func dashboard(slug: String) -> URL? {
        make(slug: slug, path: "dashboard")
    }
    // Tickets
    public static func ticketDetail(slug: String, id: Int64) -> URL? {
        make(slug: slug, path: "tickets/\(id)")
    }
    public static func newTicket(slug: String) -> URL? {
        make(slug: slug, path: "tickets/new")
    }
    // Customers
    public static func customerDetail(slug: String, id: Int64) -> URL? {
        make(slug: slug, path: "customers/\(id)")
    }
    public static func newCustomer(slug: String) -> URL? {
        make(slug: slug, path: "customers/new")
    }
    // Inventory
    public static func inventoryDetail(slug: String, sku: String) -> URL? {
        make(slug: slug, path: "inventory/\(sku)")
    }
    public static func inventoryScan(slug: String) -> URL? {
        make(slug: slug, path: "inventory/scan")
    }
    // Invoices
    public static func invoiceDetail(slug: String, id: Int64) -> URL? {
        make(slug: slug, path: "invoices/\(id)")
    }
    public static func invoicePay(slug: String, id: Int64) -> URL? {
        make(slug: slug, path: "invoices/\(id)/pay")
    }
    // Estimates
    public static func estimateDetail(slug: String, id: Int64) -> URL? {
        make(slug: slug, path: "estimates/\(id)")
    }
    // Leads
    public static func leadDetail(slug: String, id: Int64) -> URL? {
        make(slug: slug, path: "leads/\(id)")
    }
    // Appointments
    public static func appointmentDetail(slug: String, id: Int64) -> URL? {
        make(slug: slug, path: "appointments/\(id)")
    }
    // SMS
    public static func smsThread(slug: String, threadId: Int64) -> URL? {
        make(slug: slug, path: "sms/\(threadId)")
    }
    public static func newSMS(slug: String, phone: String? = nil) -> URL? {
        var url = make(slug: slug, path: "sms/new")
        if let phone, var comps = url.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) {
            comps.queryItems = [URLQueryItem(name: "phone", value: phone)]
            url = comps.url
        }
        return url
    }
    // POS
    public static func pos(slug: String) -> URL? {
        make(slug: slug, path: "pos")
    }
    public static func newSale(slug: String) -> URL? {
        make(slug: slug, path: "pos/sale/new")
    }
    public static func returns(slug: String) -> URL? {
        make(slug: slug, path: "pos/return")
    }
    // Settings
    public static func settings(slug: String, tab: String? = nil) -> URL? {
        make(slug: slug, path: tab.map { "settings/\($0)" } ?? "settings")
    }
    // Other
    public static func timeclock(slug: String) -> URL? {
        make(slug: slug, path: "timeclock")
    }
    public static func search(slug: String, query: String? = nil) -> URL? {
        var url = make(slug: slug, path: "search")
        if let q = query, var comps = url.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) {
            comps.queryItems = [URLQueryItem(name: "q", value: q)]
            url = comps.url
        }
        return url
    }
    public static func notifications(slug: String) -> URL? {
        make(slug: slug, path: "notifications")
    }
    public static func report(slug: String, name: String) -> URL? {
        make(slug: slug, path: "reports/\(name)")
    }

    // MARK: - Factory

    private static func make(slug: String, path: String) -> URL? {
        URL(string: "\(DeepLinkScheme.scheme)://\(slug)/\(path)")
    }
}

// MARK: - Destinations (parsed from inbound URL)

public enum DeepLinkDestination: Equatable, Sendable {
    case dashboard
    case ticketDetail(id: Int64)
    case newTicket
    case customerDetail(id: Int64)
    case newCustomer
    case inventoryDetail(sku: String)
    case inventoryScan
    case invoiceDetail(id: Int64)
    case invoicePay(id: Int64)
    case estimateDetail(id: Int64)
    case leadDetail(id: Int64)
    case appointmentDetail(id: Int64)
    case smsThread(id: Int64)
    case newSMS(phone: String?)
    case pos
    case newSale
    case returns
    case settings(tab: String?)
    case timeclock
    case search(query: String?)
    case notifications
    case report(name: String)
    case unknown(path: String)
}

// MARK: - Parser

public enum DeepLinkParser {
    /// Parse a `bizarrecrm://` URL.
    /// Returns nil for non-`bizarrecrm` schemes.
    public static func parse(_ url: URL) -> (slug: String, destination: DeepLinkDestination)? {
        guard url.scheme == DeepLinkScheme.scheme,
              let slug = url.host, !slug.isEmpty else { return nil }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems

        let destination = resolve(pathComponents: pathComponents, query: query)
        return (slug, destination)
    }

    private static func resolve(pathComponents: [String], query: [URLQueryItem]?) -> DeepLinkDestination {
        guard let first = pathComponents.first else { return .dashboard }

        switch first {
        case "dashboard":
            return .dashboard

        case "tickets":
            if pathComponents.count < 2 || pathComponents[1] == "new" { return .newTicket }
            if let id = Int64(pathComponents[1]) { return .ticketDetail(id: id) }
            return .unknown(path: pathComponents.joined(separator: "/"))

        case "customers":
            if pathComponents.count < 2 || pathComponents[1] == "new" { return .newCustomer }
            if let id = Int64(pathComponents[1]) { return .customerDetail(id: id) }
            return .unknown(path: pathComponents.joined(separator: "/"))

        case "inventory":
            if pathComponents.count < 2 { return .unknown(path: first) }
            if pathComponents[1] == "scan" { return .inventoryScan }
            return .inventoryDetail(sku: pathComponents[1])

        case "invoices":
            guard pathComponents.count >= 2, let id = Int64(pathComponents[1]) else {
                return .unknown(path: pathComponents.joined(separator: "/"))
            }
            if pathComponents.count >= 3, pathComponents[2] == "pay" { return .invoicePay(id: id) }
            return .invoiceDetail(id: id)

        case "estimates":
            if pathComponents.count >= 2, let id = Int64(pathComponents[1]) { return .estimateDetail(id: id) }
            return .unknown(path: pathComponents.joined(separator: "/"))

        case "leads":
            if pathComponents.count >= 2, let id = Int64(pathComponents[1]) { return .leadDetail(id: id) }
            return .unknown(path: pathComponents.joined(separator: "/"))

        case "appointments":
            if pathComponents.count >= 2, let id = Int64(pathComponents[1]) { return .appointmentDetail(id: id) }
            return .unknown(path: pathComponents.joined(separator: "/"))

        case "sms":
            if pathComponents.count >= 2 {
                if pathComponents[1] == "new" {
                    let phone = query?.first(where: { $0.name == "phone" })?.value
                    return .newSMS(phone: phone)
                }
                if let id = Int64(pathComponents[1]) { return .smsThread(id: id) }
            }
            return .unknown(path: pathComponents.joined(separator: "/"))

        case "pos":
            if pathComponents.count >= 2 {
                if pathComponents[1] == "sale", pathComponents.count >= 3, pathComponents[2] == "new" { return .newSale }
                if pathComponents[1] == "return" { return .returns }
            }
            return .pos

        case "settings":
            let tab = pathComponents.count >= 2 ? pathComponents[1] : nil
            return .settings(tab: tab)

        case "timeclock":
            return .timeclock

        case "search":
            let q = query?.first(where: { $0.name == "q" })?.value
            return .search(query: q)

        case "notifications":
            return .notifications

        case "reports":
            let name = pathComponents.count >= 2 ? pathComponents[1] : "summary"
            return .report(name: name)

        default:
            return .unknown(path: pathComponents.joined(separator: "/"))
        }
    }
}
