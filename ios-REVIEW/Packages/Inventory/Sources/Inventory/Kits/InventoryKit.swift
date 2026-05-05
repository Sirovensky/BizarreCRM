import Foundation

// MARK: - §6 Inventory Kits / BOM
//
// Server routes (packages/server/src/routes/inventory.routes.ts):
//   GET    /inventory/kits       — list all kits (id, name, description, item_count, created_at)
//   GET    /inventory/kits/:id   — kit + items[] (each row has inventory_item_id, quantity,
//                                  item_name, sku, retail_price, cost_price, in_stock)
//   POST   /inventory/kits       — create (requires inventory.create permission)
//   DELETE /inventory/kits/:id   — delete (requires inventory.delete permission)
//
// A kit is a virtual item that consumes N components from stock when sold.
// All money values are in cents to match server convention.

/// Top-level kit row as returned by GET /inventory/kits (list) and
/// GET /inventory/kits/:id (detail). The `items` array is nil on the list
/// endpoint (item_count is provided instead) and populated on the detail endpoint.
public struct InventoryKit: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let name: String
    public let description: String?
    /// Number of component lines — available on the list endpoint.
    public let itemCount: Int?
    /// Component lines — populated by the detail endpoint only.
    public let items: [InventoryKitComponent]?
    public let createdAt: String?

    public init(
        id: Int64,
        name: String,
        description: String? = nil,
        itemCount: Int? = nil,
        items: [InventoryKitComponent]? = nil,
        createdAt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.itemCount = itemCount
        self.items = items
        self.createdAt = createdAt
    }

    // MARK: Derived

    /// Sum of (component.costPrice * component.quantity) for all lines that
    /// carry a cost price. Returns nil when no components have cost data.
    public var totalCostCents: Int? {
        guard let lines = items, !lines.isEmpty else { return nil }
        let withCost = lines.compactMap { line -> Int? in
            guard let costCents = line.costPriceCents else { return nil }
            return costCents * line.quantity
        }
        guard !withCost.isEmpty else { return nil }
        return withCost.reduce(0, +)
    }

    /// Sum of (component.retailPrice * component.quantity).
    public var totalRetailCents: Int? {
        guard let lines = items, !lines.isEmpty else { return nil }
        let withRetail = lines.compactMap { line -> Int? in
            guard let retailCents = line.retailPriceCents else { return nil }
            return retailCents * line.quantity
        }
        guard !withRetail.isEmpty else { return nil }
        return withRetail.reduce(0, +)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, items
        case itemCount  = "item_count"
        case createdAt  = "created_at"
    }
}
