import Foundation

// §63 Draft recovery — DraftRecoverable protocol
// Phase 0 foundation

/// Adopting a screen type declares that it supports draft save/restore.
///
/// ```swift
/// struct TicketEditView: View, DraftRecoverable {
///     typealias Draft = TicketDraft
///     static let screenId = "ticket.edit"
///     …
/// }
/// ```
///
/// The `screenId` is used as the primary key in `DraftStore`.  Use a
/// dot-namespaced string that is stable across app versions.
public protocol DraftRecoverable {
    /// The type that represents the draft payload.
    associatedtype Draft: Codable

    /// Stable, human-readable identifier for the screen.
    /// Example: `"ticket.edit"`, `"customer.create"`, `"estimate.edit"`.
    static var screenId: String { get }
}
