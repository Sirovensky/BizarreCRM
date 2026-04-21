import Foundation

/// `GET /api/v1/inventory` response.
/// Server: packages/server/src/routes/inventory.routes.ts:60,116.
/// Envelope data: `{ items: [...], pagination: {...} }`.
public struct InventoryListResponse: Decodable, Sendable {
    public let items: [InventoryListItem]
    public let pagination: Pagination?

    public struct Pagination: Decodable, Sendable {
        public let page: Int?
        public let perPage: Int?
        public let total: Int?
        public let totalPages: Int?

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

    /// POST /api/v1/inventory/:id/adjust-stock
    /// Server: inventory.routes.ts:1097. Permission: inventory.adjust_stock (admin/manager).
    /// Returns the updated inventory row; we surface only newQty + auditId (movement id).
    func adjustStock(itemId: Int64, request: AdjustStockRequest) async throws -> AdjustStockResponse {
        do {
            return try await post(
                "/api/v1/inventory/\(itemId)/adjust-stock",
                body: request,
                as: AdjustStockResponse.self
            )
        } catch APITransportError.httpStatus(let code, _) where code == 404 || code == 501 {
            throw APITransportError.notImplemented
        }
    }

    /// GET /api/v1/inventory/low-stock
    /// Server: inventory.routes.ts:279. No permission gate — any authenticated user.
    /// Returns items where in_stock <= reorder_level.
    func listLowStock() async throws -> [LowStockItem] {
        do {
            return try await get("/api/v1/inventory/low-stock", as: [LowStockItem].self)
        } catch APITransportError.httpStatus(let code, _) where code == 404 || code == 501 {
            throw APITransportError.notImplemented
        }
    }
}

// MARK: - §6.5 Adjust-stock DTOs

/// Request body for `POST /api/v1/inventory/:id/adjust-stock`.
/// Server reads `quantity` (Int), `type` (String), `notes` (String?).
public struct AdjustStockRequest: Encodable, Sendable {
    /// Signed integer — positive to add, negative to remove.
    public let deltaQty: Int
    /// Reason code matching server's stock_movement.type column.
    public let reason: String
    public let notes: String?

    public init(deltaQty: Int, reason: String, notes: String? = nil) {
        self.deltaQty = deltaQty
        self.reason = reason
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case deltaQty = "quantity"
        case reason = "type"
        case notes
    }
}

/// Decoded from the updated inventory row the server echoes back.
/// The server returns the full inventory_items row; we decode a subset.
public struct AdjustStockResponse: Decodable, Sendable {
    public let newQty: Int
    /// Last inserted stock_movement row id — used by callers as an audit handle.
    public let auditId: Int64

    /// Memberwise init — used by tests and callers that construct a value directly.
    public init(newQty: Int, auditId: Int64) {
        self.newQty = newQty
        self.auditId = auditId
    }

    enum CodingKeys: String, CodingKey {
        case newQty = "in_stock"
        case auditId = "last_movement_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.newQty = try c.decode(Int.self, forKey: .newQty)
        // last_movement_id is not always present in the row echo; fall back to 0.
        self.auditId = (try? c.decode(Int64.self, forKey: .auditId)) ?? 0
    }
}

// MARK: - §6.6 Low-stock DTOs

/// One item returned by `GET /api/v1/inventory/low-stock`.
/// The server selects `SELECT * FROM inventory_items` so all columns are available;
/// we only decode what the UI needs.
public struct LowStockItem: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let name: String
    public let sku: String?
    public let currentQty: Int
    public let reorderThreshold: Int

    /// How many units short of the reorder threshold this item is.
    public var shortageBy: Int { max(0, reorderThreshold - currentQty) }

    enum CodingKeys: String, CodingKey {
        case id, name, sku
        case currentQty = "in_stock"
        case reorderThreshold = "reorder_level"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int64.self, forKey: .id)
        self.name = (try? c.decode(String.self, forKey: .name)) ?? "Unnamed"
        self.sku = try? c.decode(String.self, forKey: .sku)
        self.currentQty = (try? c.decode(Int.self, forKey: .currentQty)) ?? 0
        self.reorderThreshold = (try? c.decode(Int.self, forKey: .reorderThreshold)) ?? 0
    }
}
