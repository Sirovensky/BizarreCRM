import Foundation
import Core
#if canImport(UIKit)
import UIKit
#endif

// MARK: - §25.7 Universal Links — cloud-hosted tenants only
//
// When a user taps `https://app.bizarrecrm.com/tickets/123` or
// `https://<tenant-slug>.bizarrecrm.com/tickets/123` iOS validates the
// associated-domains entitlement (`applinks:app.bizarrecrm.com` +
// `applinks:*.bizarrecrm.com`) then calls
// `scene(_:continue:)` / `onContinueUserActivity(.browsingWeb)`.
//
// This file provides `UniversalLinkHandler`, a pure route-extractor that:
//  1. Validates the host is a known bizarrecrm.com domain.
//  2. Extracts the path and maps it to a `DeepLinkDestination`.
//  3. Applies the login gate: if the user is not authenticated, stores the
//     intent in `PendingUniversalLink` and the auth flow restores it after login.
//  4. Returns nil (→ fallback to web) for unknown paths.
//
// Associated domains are added to BizarreCRM.entitlements by Agent 10.
// This file is the iOS-layer handler only.

// MARK: - Pending storage

/// Stores an unhandled Universal Link across the auth wall.
/// On login success, `SessionBootstrapper` reads + clears this and re-routes.
public enum PendingUniversalLink {
    private static let key = "pending.universalLink"

    public static func store(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: key)
    }

    public static func consume() -> URL? {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let url = URL(string: raw) else { return nil }
        UserDefaults.standard.removeObject(forKey: key)
        return url
    }
}

// MARK: - Handler

/// Pure URL → `DeepLinkDestination?` converter for Universal Links.
///
/// Parsing rules (§65.1):
/// - `https://app.bizarrecrm.com/c/:shortCode`             → `.dashboard` (short-code resolver TBD server-side)
/// - `https://app.bizarrecrm.com/track/:token`             → `.unknown` (public customer page, don't intercept)
/// - `https://app.bizarrecrm.com/pay/:token`               → `.unknown` (public page)
/// - `https://app.bizarrecrm.com/review/:token`            → `.unknown` (public page)
/// - `https://<slug>.bizarrecrm.com/<path>`                → same as `bizarrecrm://<slug>/<path>`
/// - `https://app.bizarrecrm.com/<path>` (staff routes)    → same as `bizarrecrm://default/<path>`
public enum UniversalLinkHandler {

    // Domains covered by the entitlement.
    private static let primaryHost = "app.bizarrecrm.com"
    private static let primaryTLD  = ".bizarrecrm.com"

    // Public customer-facing paths — these stay in Safari.
    private static let publicPathPrefixes: Set<String> = [
        "track", "pay", "review", "book", "public"
    ]

    /// Attempts to route a Universal Link.
    ///
    /// - Returns: A `(slug, destination)` pair if the URL is a known staff route,
    ///   or `nil` if it should fall back to the web browser.
    public static func handle(_ url: URL) -> (slug: String, destination: DeepLinkDestination)? {
        guard let host = url.host?.lowercased() else { return nil }

        // Must be a bizarrecrm.com domain
        guard host == primaryHost || host.hasSuffix(primaryTLD) else { return nil }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard let firstPath = pathComponents.first else {
            // Bare domain → dashboard
            let slug = extractSlug(from: host)
            return (slug, .dashboard)
        }

        // Skip public customer-facing paths — let them open in Safari
        if publicPathPrefixes.contains(firstPath.lowercased()) { return nil }

        // Extract slug from subdomain or fall back to "default"
        let slug = extractSlug(from: host)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems

        let destination = resolveStaffPath(pathComponents: pathComponents, query: query)
        return (slug, destination)
    }

    // MARK: - Private

    private static func extractSlug(from host: String) -> String {
        if host == primaryHost { return "default" }
        if host.hasSuffix(primaryTLD) {
            let slug = String(host.dropLast(primaryTLD.count))
            return slug.isEmpty ? "default" : slug
        }
        return "default"
    }

    private static func resolveStaffPath(
        pathComponents: [String],
        query: [URLQueryItem]?
    ) -> DeepLinkDestination {
        guard let first = pathComponents.first?.lowercased() else { return .dashboard }
        switch first {
        case "t", "tickets":
            if pathComponents.count < 2 { return .unknown(path: first) }
            if let id = Int64(pathComponents[1]) { return .ticketDetail(id: id) }
            return .unknown(path: first)
        case "c", "customers":
            if pathComponents.count < 2 { return .unknown(path: first) }
            if let id = Int64(pathComponents[1]) { return .customerDetail(id: id) }
            return .unknown(path: first)
        case "i", "invoices":
            if pathComponents.count < 2 { return .unknown(path: first) }
            if let id = Int64(pathComponents[1]) {
                if pathComponents.count >= 3, pathComponents[2] == "pay" { return .invoicePay(id: id) }
                return .invoiceDetail(id: id)
            }
            return .unknown(path: first)
        case "estimates":
            if pathComponents.count >= 2, let id = Int64(pathComponents[1]) { return .estimateDetail(id: id) }
            return .unknown(path: first)
        case "appointments":
            if pathComponents.count >= 2, let id = Int64(pathComponents[1]) { return .appointmentDetail(id: id) }
            return .unknown(path: first)
        case "pos":
            return .pos
        case "settings":
            let tab = pathComponents.count >= 2 ? pathComponents[1] : nil
            return .settings(tab: tab)
        case "dashboard":
            return .dashboard
        case "search":
            let q = query?.first(where: { $0.name == "q" })?.value
            return .search(query: q)
        case "notifications":
            return .notifications
        default:
            return .unknown(path: pathComponents.joined(separator: "/"))
        }
    }
}
