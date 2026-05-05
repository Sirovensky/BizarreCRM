import Foundation

/// §16.14 — A cart snapshot saved to the "held carts" queue.
/// Persisted in UserDefaults for MVP; TODO migrate to GRDB.
public struct HeldCart: Identifiable, Codable, Sendable {
    public let id:         UUID
    public let savedAt:    Date
    public let cart:       CartSnapshot
    public let customerId: Int64?
    public let ticketId:   Int64?
    public let note:       String?

    public init(
        id:         UUID        = UUID(),
        savedAt:    Date        = Date(),
        cart:       CartSnapshot,
        customerId: Int64?      = nil,
        ticketId:   Int64?      = nil,
        note:       String?     = nil
    ) {
        self.id         = id
        self.savedAt    = savedAt
        self.cart       = cart
        self.customerId = customerId
        self.ticketId   = ticketId
        self.note       = note
    }

    /// Carts older than 24 h are auto-expired.
    public var isExpired: Bool {
        Date().timeIntervalSince(savedAt) > 24 * 60 * 60
    }

    // MARK: - Display helpers

    public var displayTitle: String {
        note ?? "Hold #\(id.uuidString.prefix(6).uppercased())"
    }

    public var itemCount: Int { cart.items.count }

    public var totalCents: Int {
        cart.items.reduce(0) { acc, item in
            acc + item.unitPriceCents * item.quantity - item.discountCents
        }
    }
}
