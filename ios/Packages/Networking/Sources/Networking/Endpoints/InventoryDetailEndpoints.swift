import Foundation

/// `GET /api/v1/inventory/:id` response (unwrapped).
/// Server: packages/server/src/routes/inventory.routes.ts:775–815.
/// `data: { item, movements, group_prices }`.
public struct InventoryDetailResponse: Decodable, Sendable {
    public let item: InventoryItemDetail
    public let movements: [StockMovement]?
    public let groupPrices: [GroupPrice]?

    public struct GroupPrice: Decodable, Sendable, Identifiable, Hashable {
        public let id: Int64
        public let groupId: Int64?
        public let groupName: String?
        public let price: Double?

        enum CodingKeys: String, CodingKey {
            case id, price
            case groupId = "group_id"
            case groupName = "group_name"
        }
    }

    public struct StockMovement: Decodable, Sendable, Identifiable, Hashable {
        public let id: Int64
        public let type: String?
        public let quantity: Double?
        public let reason: String?
        public let reference: String?
        public let userName: String?
        public let createdAt: String?

        enum CodingKeys: String, CodingKey {
            case id, type, quantity, reason, reference
            case userName = "user_name"
            case createdAt = "created_at"
        }
    }

    enum CodingKeys: String, CodingKey {
        case item, movements
        case groupPrices = "group_prices"
    }
}

public struct InventoryItemDetail: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let name: String?
    public let itemType: String?
    public let description: String?
    public let sku: String?
    public let upcCode: String?
    public let inStock: Int?
    public let reorderLevel: Int?
    public let costPrice: Double?
    public let retailPrice: Double?
    public let manufacturerName: String?
    public let supplierName: String?
    public let deviceName: String?
    public let image: String?
    public let stockWarning: String?
    public let isSerialized: Int?
    public let createdAt: String?
    public let updatedAt: String?

    public var displayName: String { name?.isEmpty == false ? name! : "Unnamed" }

    public var isLowStock: Bool {
        guard let stock = inStock, let reorder = reorderLevel, reorder > 0 else { return false }
        return stock <= reorder
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, sku, image
        case itemType = "item_type"
        case upcCode = "upc_code"
        case inStock = "in_stock"
        case reorderLevel = "reorder_level"
        case costPrice = "cost_price"
        case retailPrice = "retail_price"
        case manufacturerName = "manufacturer_name"
        case supplierName = "supplier_name"
        case deviceName = "device_name"
        case stockWarning = "stock_warning"
        case isSerialized = "is_serialized"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public extension APIClient {
    func inventoryItem(id: Int64) async throws -> InventoryDetailResponse {
        try await get("/api/v1/inventory/\(id)", as: InventoryDetailResponse.self)
    }
}
