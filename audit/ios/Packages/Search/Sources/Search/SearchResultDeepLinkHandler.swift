import Foundation
import Core

// MARK: - SearchResultDeepLinkHandler

/// Converts a tapped search result (local `SearchHit` or a remote result row) into
/// a `SpotlightDeepLinkDestination` that the app-shell router can navigate to.
///
/// This mirrors what `SpotlightDeepLinkResolver` does for Spotlight taps, but
/// operates on the Search package's own `SearchHit` / `SearchResultMerger.MergedRow`
/// types so the search UI does not need to depend on CoreSpotlight at all.
///
/// **Usage:**
/// ```swift
/// MergedResultRow(row: row, …)
///     .onTapGesture {
///         if let dest = SearchResultDeepLinkHandler.destination(for: row) {
///             appRouter.navigate(to: dest)
///         }
///     }
/// ```
///
/// The handler is a stateless `enum` namespace — safe to call from any concurrency context.
public enum SearchResultDeepLinkHandler {

    // MARK: - Entity string constants

    /// Entity domain strings used in `SearchHit.entity` and `MergedRow.entity`.
    public enum Domain {
        public static let tickets      = "tickets"
        public static let customers    = "customers"
        public static let inventory    = "inventory"
        public static let invoices     = "invoices"
        public static let estimates    = "estimates"
        public static let appointments = "appointments"
    }

    // MARK: - Navigation destination (app-shell contract)

    /// The destination the app-shell should navigate to when a search result is tapped.
    ///
    /// Cases deliberately mirror `SpotlightDeepLinkDestination` for easy bridging,
    /// and extend it with additional entity types that appear in search but not Spotlight.
    public enum Destination: Sendable, Equatable {
        case ticket(id: Int64)
        case customer(id: Int64)
        case inventoryItem(id: Int64)
        case invoice(id: Int64)
        case estimate(id: Int64)
        case appointment(id: Int64)
    }

    // MARK: - SearchHit → Destination

    /// Resolve a local `SearchHit` from FTS into a navigation `Destination`.
    ///
    /// Returns `nil` if the entity domain is unrecognised or the entity ID cannot
    /// be parsed as an `Int64`.
    public static func destination(for hit: SearchHit) -> Destination? {
        guard let entityId = Int64(hit.entityId) else {
            AppLog.ui.warning(
                "SearchResultDeepLinkHandler: non-numeric entityId '\(hit.entityId, privacy: .public)' for entity '\(hit.entity, privacy: .public)'"
            )
            return nil
        }
        return destination(entity: hit.entity, entityId: entityId)
    }

    // MARK: - MergedRow → Destination

    /// Resolve a `SearchResultMerger.MergedRow` (local or remote) into a `Destination`.
    ///
    /// Returns `nil` if the entity domain is unrecognised or the ID string is non-numeric.
    public static func destination(for row: SearchResultMerger.MergedRow) -> Destination? {
        guard let entityId = Int64(row.entityId) else {
            AppLog.ui.warning(
                "SearchResultDeepLinkHandler: non-numeric entityId '\(row.entityId, privacy: .public)' for entity '\(row.entity, privacy: .public)'"
            )
            return nil
        }
        return destination(entity: row.entity, entityId: entityId)
    }

    // MARK: - Raw entity + ID → Destination

    /// Resolve from a raw entity-domain string and a numeric entity ID.
    ///
    /// This is the primitive that both `SearchHit` and `MergedRow` overloads call.
    /// Exposed `public` so the app-shell can bridge ad-hoc result types without
    /// taking a hard dependency on package-internal types.
    ///
    /// - Parameters:
    ///   - entity: The entity domain string (e.g. `"tickets"`, `"customers"`).
    ///   - entityId: The numeric entity ID.
    /// - Returns: A typed `Destination`, or `nil` for an unknown domain.
    public static func destination(entity: String, entityId: Int64) -> Destination? {
        switch entity {
        case Domain.tickets:
            return .ticket(id: entityId)
        case Domain.customers:
            return .customer(id: entityId)
        case Domain.inventory:
            return .inventoryItem(id: entityId)
        case Domain.invoices:
            return .invoice(id: entityId)
        case Domain.estimates:
            return .estimate(id: entityId)
        case Domain.appointments:
            return .appointment(id: entityId)
        default:
            AppLog.ui.warning(
                "SearchResultDeepLinkHandler: unrecognised entity domain '\(entity, privacy: .public)'"
            )
            return nil
        }
    }

    // MARK: - Spotlight bridge

    /// Bridge a `Destination` to a `SpotlightDeepLinkDestination` where the
    /// kinds overlap (ticket, customer, inventory).  Returns `nil` for entity
    /// types that exist in search but not in Spotlight (invoices, estimates, appointments).
    public static func spotlightDestination(from destination: Destination) -> SpotlightDeepLinkDestination? {
        switch destination {
        case .ticket(let id):        return .ticket(id: id)
        case .customer(let id):      return .customer(id: id)
        case .inventoryItem(let id): return .inventoryItem(id: id)
        default:                     return nil
        }
    }
}
