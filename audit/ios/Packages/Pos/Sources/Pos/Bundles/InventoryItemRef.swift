import Foundation

// MARK: - InventoryItemRef
//
// Lightweight value representing one inventory item in the context of a
// service bundle resolution.  Only the fields needed by the cart + UI are
// included; full detail lives in InventoryListItem / InventoryItemDetail.

/// A lightweight reference to an inventory item returned as part of a
/// `BundleResolution`.  Immutable and `Sendable` — safe to pass across
/// actor boundaries.
public struct InventoryItemRef: Equatable, Hashable, Sendable {
    /// `inventory_items.id` primary key.
    public let id: Int64
    /// Unique stock-keeping unit.
    public let sku: String
    /// Display name (e.g. "iPhone 14 Pro Screen — OEM").
    public let name: String
    /// Retail price in cents.  Zero is a valid price (e.g. warranty part).
    public let priceCents: Int
    /// `true` when the item is a labour / service line (no physical stock).
    public let isService: Bool
    /// Current stock quantity. `nil` means stock info was unavailable.
    public let stockQty: Int?

    public init(
        id: Int64,
        sku: String,
        name: String,
        priceCents: Int,
        isService: Bool,
        stockQty: Int? = nil
    ) {
        self.id = id
        self.sku = sku
        self.name = name
        self.priceCents = max(0, priceCents)
        self.isService = isService
        self.stockQty = stockQty
    }
}

// MARK: - Decodable

extension InventoryItemRef: Decodable {
    enum CodingKeys: String, CodingKey {
        case id, sku, name
        case priceCents  = "price_cents"
        case isService   = "is_service"
        case stockQty    = "stock_qty"
    }
}

// MARK: - Convenience

public extension InventoryItemRef {
    /// `true` when the stock qty is known and is zero or below.
    var isOutOfStock: Bool {
        guard let qty = stockQty else { return false }
        return qty <= 0
    }

    /// `true` when the stock qty is known and positive — not exhaustive.
    var isInStock: Bool {
        guard let qty = stockQty else { return true }   // unknown → assume in stock
        return qty > 0
    }
}
