import Foundation

// MARK: - SpotlightDeepLinkDestination

/// The navigation destination resolved from a `SpotlightEntityReference`.
///
/// The app-shell switches on this enum in its router/coordinator to push the
/// correct detail screen. Values are intentionally value types (`Sendable`) so
/// they can be passed across actor boundaries safely.
///
/// **Example routing (app-shell, NOT owned by this package):**
/// ```swift
/// switch destination {
/// case .ticket(let id):
///     navigator.push(.ticketDetail(id: id))
/// case .customer(let id):
///     navigator.push(.customerDetail(id: id))
/// case .inventoryItem(let id):
///     navigator.push(.inventoryDetail(id: id))
/// }
/// ```
public enum SpotlightDeepLinkDestination: Sendable, Equatable {
    /// Navigate to the ticket detail screen for `id`.
    case ticket(id: Int64)
    /// Navigate to the customer detail screen for `id`.
    case customer(id: Int64)
    /// Navigate to the inventory item detail screen for `id`.
    case inventoryItem(id: Int64)
}

// MARK: - SpotlightDeepLinkResolver

/// Converts a `SpotlightEntityReference` into a `SpotlightDeepLinkDestination`
/// that the app-shell router can consume.
///
/// Stateless — all methods are `static` so no instance is required.
///
/// **Typical call-site (app-shell):**
/// ```swift
/// .onContinueUserActivity(CSSearchableItemActionType) { activity in
///     guard let ref = SpotlightActivityHandler.entityReference(from: activity) else { return }
///     let dest = SpotlightDeepLinkResolver.destination(for: ref)
///     AppRouter.shared.navigate(to: dest)
/// }
/// ```
public enum SpotlightDeepLinkResolver {

    // MARK: - Public API

    /// Resolve a `SpotlightEntityReference` into a navigation destination.
    ///
    /// The mapping is a 1-to-1 projection of `EntityKind` onto the concrete
    /// destination cases, carrying the entity ID through unchanged.
    ///
    /// - Parameter reference: The entity reference produced by
    ///   `SpotlightActivityHandler.entityReference(from:)`.
    /// - Returns: The `SpotlightDeepLinkDestination` the app-shell should navigate to.
    public static func destination(for reference: SpotlightEntityReference) -> SpotlightDeepLinkDestination {
        switch reference.kind {
        case .ticket:
            return .ticket(id: reference.entityId)
        case .customer:
            return .customer(id: reference.entityId)
        case .inventory:
            return .inventoryItem(id: reference.entityId)
        }
    }

    /// Convenience overload that parses an identifier string directly.
    ///
    /// Returns `nil` if the identifier is malformed or the domain is unknown.
    ///
    /// - Parameter uniqueIdentifier: A raw Spotlight unique identifier string
    ///   in the format `"bizarrecrm.<kind>.<id>"`.
    public static func destination(forIdentifier uniqueIdentifier: String) -> SpotlightDeepLinkDestination? {
        guard let ref = SpotlightActivityHandler.parse(uniqueIdentifier: uniqueIdentifier) else {
            return nil
        }
        return destination(for: ref)
    }
}
