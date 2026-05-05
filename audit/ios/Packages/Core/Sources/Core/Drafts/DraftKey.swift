import Foundation

// §20 Draft Recovery — DraftKey
// Strongly-typed composite key for addressing a draft in the store.
// Format on disk: "<entityKind>|<id>" or "<entityKind>|" when id is nil.

/// A strongly-typed key that uniquely identifies a draft.
///
/// Use one of the static factory helpers for well-known screens:
/// ```swift
/// let key = DraftKey.ticketCreate
/// let key = DraftKey.ticketEdit(id: "42")
/// let key = DraftKey.customerCreate
/// ```
/// Or construct a custom key for extension points:
/// ```swift
/// let key = DraftKey(entityKind: "invoice.edit", id: "99")
/// ```
public struct DraftKey: Hashable, Codable, Sendable, CustomStringConvertible {

    // MARK: — Properties

    /// Dot-namespaced screen / entity kind (e.g. `"ticket.create"`, `"customer.edit"`).
    /// Must be stable across app versions — changing it orphans existing drafts.
    public let entityKind: String

    /// Optional entity identifier for edit flows. `nil` for create flows.
    public let id: String?

    // MARK: — Init

    public init(entityKind: String, id: String? = nil) {
        self.entityKind = entityKind
        self.id = id
    }

    // MARK: — Well-known keys

    // Tickets
    public static let ticketCreate        = DraftKey(entityKind: "ticket.create")
    public static func ticketEdit(id: String) -> DraftKey { DraftKey(entityKind: "ticket.edit", id: id) }

    // Customers
    public static let customerCreate      = DraftKey(entityKind: "customer.create")
    public static func customerEdit(id: String) -> DraftKey { DraftKey(entityKind: "customer.edit", id: id) }

    // Estimates
    public static let estimateCreate      = DraftKey(entityKind: "estimate.create")
    public static func estimateEdit(id: String) -> DraftKey { DraftKey(entityKind: "estimate.edit", id: id) }

    // Invoices
    public static let invoiceCreate       = DraftKey(entityKind: "invoice.create")
    public static func invoiceEdit(id: String) -> DraftKey { DraftKey(entityKind: "invoice.edit", id: id) }

    // Field-service jobs
    public static let jobCreate           = DraftKey(entityKind: "job.create")
    public static func jobEdit(id: String) -> DraftKey { DraftKey(entityKind: "job.edit", id: id) }

    // MARK: — Internal helpers

    /// Stable composite string used as the UserDefaults key fragment.
    /// Format: `"<entityKind>|<id>"` or `"<entityKind>|"` when `id` is nil.
    var storageKey: String { "\(entityKind)|\(id ?? "")" }

    // MARK: — CustomStringConvertible

    public var description: String { storageKey }
}
