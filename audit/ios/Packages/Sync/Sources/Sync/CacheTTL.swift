import Foundation

// §20.1 — TTL per domain
//
// Centralised maxAge values for `CachedRepository.list(filter:maxAgeSeconds:)`.
// Keep these in one place so we don't sprinkle magic-number `60` / `300` calls
// across every repository.
//
// Per the iOS ActionPlan §20.1:
//   - tickets   30s
//   - inventory 60s
//   - customers 5min
//   - reports   2min
//   - settings  10min
//
// Usage:
//
//   try await ticketsRepository.list(filter: .all, maxAgeSeconds: CacheTTL.tickets)

public enum CacheTTL {
    /// 30s — tickets churn fast (assignment, status changes, photos).
    public static let tickets:   Int = 30
    /// 60s — inventory quantity-on-hand can move via POS sales / receiving.
    public static let inventory: Int = 60
    /// 5min — customer profiles are mostly static between mutations.
    public static let customers: Int = 5 * 60
    /// 2min — reports are aggregations; recompute frequently but not per-tap.
    public static let reports:   Int = 2 * 60
    /// 10min — tenant settings rarely change mid-session.
    public static let settings:  Int = 10 * 60

    // MARK: - Domain helpers

    /// Look up the right TTL for a given entity name. Falls back to 60s when
    /// the entity isn't recognised — better than every caller picking a value.
    public static func ttl(for entity: String) -> Int {
        switch entity.lowercased() {
        case "ticket", "tickets":         return tickets
        case "inventory", "items":        return inventory
        case "customer", "customers":     return customers
        case "report", "reports":         return reports
        case "setting", "settings":       return settings
        default:                          return 60
        }
    }
}
