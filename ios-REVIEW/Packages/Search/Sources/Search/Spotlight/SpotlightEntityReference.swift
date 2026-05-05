import Foundation

// MARK: - SpotlightEntityReference

/// A strongly-typed reference to a BizarreCRM entity extracted from a
/// CoreSpotlight `NSUserActivity`.
///
/// Produced by `SpotlightActivityHandler.entityReference(from:)` and
/// consumed by `SpotlightDeepLinkResolver` to produce a navigation
/// destination the app-shell can act on.
///
/// The unique-identifier format is `"bizarrecrm.<domain>.<id>"`, which
/// mirrors `SpotlightIndexable.spotlightUniqueIdentifier`.
public struct SpotlightEntityReference: Sendable, Equatable {

    // MARK: - EntityKind

    /// The BizarreCRM domain the reference belongs to.
    public enum EntityKind: String, Sendable, Equatable, CaseIterable {
        case ticket    = "ticket"
        case customer  = "customer"
        case inventory = "inventory"
    }

    // MARK: Properties

    /// The entity kind (domain).
    public let kind: EntityKind

    /// The numeric entity ID parsed from the unique identifier.
    public let entityId: Int64

    /// The raw Spotlight unique identifier, e.g. `"bizarrecrm.ticket.42"`.
    public let uniqueIdentifier: String

    // MARK: Init

    /// Designated init — prefer using `SpotlightActivityHandler` rather than
    /// constructing directly.
    public init(kind: EntityKind, entityId: Int64, uniqueIdentifier: String) {
        self.kind = kind
        self.entityId = entityId
        self.uniqueIdentifier = uniqueIdentifier
    }
}
