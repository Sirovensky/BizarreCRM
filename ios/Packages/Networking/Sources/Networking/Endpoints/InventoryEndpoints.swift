import Foundation

/// `GET /api/v1/inventory` response.
/// Server: packages/server/src/routes/inventory.routes.ts:60,116.
/// Envelope data: `{ items: [...], pagination: {...} }`.
public struct InventoryListResponse: Decodable, Sendable {
    public let items: [InventoryListItem]
    public let pagination: Pagination?

    public struct Pagination: Decodable, Sendable {
        public let page: Int
        public let perPage: Int
        public let total: Int
        public let totalPages: Int

        enum CodingKeys: String, CodingKey {
            case page, total
            case perPage = "per_page"
            case totalPages = "total_pages"
        }
    }
}

public struct InventoryListItem: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let name: String?
    public let itemType: String?
    public let sku: String?
    public let upcCode: String?
    public let inStock: Int?
    public let reorderLevel: Int?
    public let costPrice: Double?     // admin/manager only — may be nil
    public let retailPrice: Double?
    public let manufacturerName: String?
    public let deviceName: String?
    public let supplierName: String?
    public let isSerialized: Int?

    public var displayName: String { name?.isEmpty == false ? name! : "Unnamed" }

    public var isLowStock: Bool {
        guard let stock = inStock, let reorder = reorderLevel, reorder > 0 else { return false }
        return stock <= reorder
    }

    public var priceCents: Int? {
        guard let retail = retailPrice else { return nil }
        return Int((retail * 100).rounded())
    }

    enum CodingKeys: String, CodingKey {
        case id, name, sku
        case itemType = "item_type"
        case upcCode = "upc_code"
        case inStock = "in_stock"
        case reorderLevel = "reorder_level"
        case costPrice = "cost_price"
        case retailPrice = "retail_price"
        case manufacturerName = "manufacturer_name"
        case deviceName = "device_name"
        case supplierName = "supplier_name"
        case isSerialized = "is_serialized"
    }
}

public enum InventoryFilter: String, CaseIterable, Sendable, Identifiable {
    case all
    case product
    case part
    case lowStock

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all:      return "All"
        case .product:  return "Product"
        case .part:     return "Part"
        case .lowStock: return "Low stock"
        }
    }

    public var queryItems: [URLQueryItem] {
        switch self {
        case .all:      return []
        case .product:  return [URLQueryItem(name: "item_type", value: "product")]
        case .part:     return [URLQueryItem(name: "item_type", value: "part")]
        case .lowStock: return [URLQueryItem(name: "low_stock", value: "true")]
        }
    }
}

public extension APIClient {
    func listInventory(filter: InventoryFilter = .all, keyword: String? = nil, pageSize: Int = 50) async throws -> InventoryListResponse {
        var items = filter.queryItems
        items.append(URLQueryItem(name: "pagesize", value: String(pageSize)))
        if let keyword, !keyword.isEmpty {
            items.append(URLQueryItem(name: "keyword", value: keyword))
        }
        return try await get("/api/v1/inventory", query: items, as: InventoryListResponse.self)
    }
}
