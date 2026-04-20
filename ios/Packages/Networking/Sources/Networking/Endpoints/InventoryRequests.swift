import Foundation

// MARK: - Inventory create

/// `POST /api/v1/inventory` request body.
/// Server: packages/server/src/routes/inventory.routes.ts:944.
///
/// Required: `name`, `item_type` (enum — "product" | "part" | "service").
/// Server validates prices + quantities and auto-generates SKU when blank —
/// we still send ours so the operator can dictate it.
public struct CreateInventoryItemRequest: Codable, Sendable {
    public let name: String
    public let itemType: String
    public let sku: String?
    public let upc: String?
    public let description: String?
    public let category: String?
    public let manufacturer: String?
    public let costPrice: Double?
    public let retailPrice: Double?
    public let inStock: Int?
    public let reorderLevel: Int?
    public let supplierId: Int64?

    public init(name: String,
                itemType: String = "product",
                sku: String? = nil,
                upc: String? = nil,
                description: String? = nil,
                category: String? = nil,
                manufacturer: String? = nil,
                costPrice: Double? = nil,
                retailPrice: Double? = nil,
                inStock: Int? = nil,
                reorderLevel: Int? = nil,
                supplierId: Int64? = nil) {
        self.name = name
        self.itemType = itemType
        self.sku = sku
        self.upc = upc
        self.description = description
        self.category = category
        self.manufacturer = manufacturer
        self.costPrice = costPrice
        self.retailPrice = retailPrice
        self.inStock = inStock
        self.reorderLevel = reorderLevel
        self.supplierId = supplierId
    }

    enum CodingKeys: String, CodingKey {
        case name, sku, upc, description, category, manufacturer
        case itemType = "item_type"
        case costPrice = "cost_price"
        case retailPrice = "retail_price"
        case inStock = "in_stock"
        case reorderLevel = "reorder_level"
        case supplierId = "supplier_id"
    }
}

// MARK: - Inventory update

/// `PUT /api/v1/inventory/:id` request body.
/// Server: packages/server/src/routes/inventory.routes.ts:1011.
///
/// All fields are optional — the server uses COALESCE to preserve missing
/// keys, so omit to leave a column untouched. Send empty string to clear a
/// nullable field (per route comment at line 1054).
public struct UpdateInventoryItemRequest: Codable, Sendable {
    public let name: String?
    public let itemType: String?
    public let sku: String?
    public let upc: String?
    public let description: String?
    public let category: String?
    public let manufacturer: String?
    public let costPrice: Double?
    public let retailPrice: Double?
    public let reorderLevel: Int?
    public let supplierId: Int64?

    public init(name: String? = nil,
                itemType: String? = nil,
                sku: String? = nil,
                upc: String? = nil,
                description: String? = nil,
                category: String? = nil,
                manufacturer: String? = nil,
                costPrice: Double? = nil,
                retailPrice: Double? = nil,
                reorderLevel: Int? = nil,
                supplierId: Int64? = nil) {
        self.name = name
        self.itemType = itemType
        self.sku = sku
        self.upc = upc
        self.description = description
        self.category = category
        self.manufacturer = manufacturer
        self.costPrice = costPrice
        self.retailPrice = retailPrice
        self.reorderLevel = reorderLevel
        self.supplierId = supplierId
    }

    enum CodingKeys: String, CodingKey {
        case name, sku, upc, description, category, manufacturer
        case itemType = "item_type"
        case costPrice = "cost_price"
        case retailPrice = "retail_price"
        case reorderLevel = "reorder_level"
        case supplierId = "supplier_id"
    }
}

public extension APIClient {
    /// Server responds `201 { success: true, data: <full row> }`. We decode
    /// only `id` for navigation — mirrors `createCustomer`'s contract.
    func createInventoryItem(_ req: CreateInventoryItemRequest) async throws -> CreatedResource {
        try await post("/api/v1/inventory", body: req, as: CreatedResource.self)
    }

    /// Server responds `200 { success: true, data: <full row> }`.
    func updateInventoryItem(id: Int64, _ req: UpdateInventoryItemRequest) async throws -> CreatedResource {
        try await put("/api/v1/inventory/\(id)", body: req, as: CreatedResource.self)
    }
}
