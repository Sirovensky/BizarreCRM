import Foundation

// MARK: - InventoryKitComponent
//
// Mirrors one row from:
//   SELECT ki.*, i.name AS item_name, i.sku, i.retail_price, i.cost_price, i.in_stock
//   FROM inventory_kit_items ki
//   JOIN inventory_items i ON i.id = ki.inventory_item_id
//   WHERE ki.kit_id = ?
//
// Server column names (snake_case) → Swift property names (camelCase).

/// One component line inside a kit.
/// All money values are in cents, matching server convention.
public struct InventoryKitComponent: Decodable, Sendable, Identifiable, Hashable {
    /// Primary key of the `inventory_kit_items` row.
    public let id: Int64
    public let kitId: Int64
    public let inventoryItemId: Int64
    /// Number of units of this component consumed per kit sold.
    public let quantity: Int
    /// Human-readable name from the joined `inventory_items` row.
    public let itemName: String?
    public let sku: String?
    /// Retail price in cents (may be nil for service items).
    public let retailPriceCents: Int?
    /// Cost price in cents (may be nil).
    public let costPriceCents: Int?
    /// Current on-hand stock (nil on list endpoint, present on detail).
    public let inStock: Int?

    public init(
        id: Int64,
        kitId: Int64,
        inventoryItemId: Int64,
        quantity: Int,
        itemName: String? = nil,
        sku: String? = nil,
        retailPriceCents: Int? = nil,
        costPriceCents: Int? = nil,
        inStock: Int? = nil
    ) {
        self.id = id
        self.kitId = kitId
        self.inventoryItemId = inventoryItemId
        self.quantity = quantity
        self.itemName = itemName
        self.sku = sku
        self.retailPriceCents = retailPriceCents
        self.costPriceCents = costPriceCents
        self.inStock = inStock
    }

    // MARK: Derived

    /// True when current stock is lower than the quantity needed per kit.
    /// Returns nil when `inStock` is not available.
    public var isStockInsufficient: Bool? {
        guard let stock = inStock else { return nil }
        return stock < quantity
    }

    /// Extended cost for this line: costPriceCents * quantity.
    public var extendedCostCents: Int? {
        costPriceCents.map { $0 * quantity }
    }

    /// Extended retail for this line: retailPriceCents * quantity.
    public var extendedRetailCents: Int? {
        retailPriceCents.map { $0 * quantity }
    }

    enum CodingKeys: String, CodingKey {
        case id, quantity, sku
        case kitId            = "kit_id"
        case inventoryItemId  = "inventory_item_id"
        case itemName         = "item_name"
        case retailPriceCents = "retail_price"
        case costPriceCents   = "cost_price"
        case inStock          = "in_stock"
    }
}
