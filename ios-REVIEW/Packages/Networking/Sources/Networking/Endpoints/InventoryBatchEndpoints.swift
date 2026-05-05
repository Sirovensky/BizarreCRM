import Foundation

// MARK: - Batch update DTOs

/// Field updates for `POST /api/v1/inventory/items/batch`.
/// Send only the fields to update — omit (nil) to leave untouched.
public struct BatchInventoryUpdates: Encodable, Sendable {
    /// Percentage adjustment to retail price. e.g. 10 = +10%, -5 = -5%.
    public let priceAdjustPercent: Double?
    /// Reassign all selected items to this category.
    public let category: String?
    /// Replace tags on all selected items.
    public let tags: [String]?

    public init(priceAdjustPercent: Double? = nil,
                category: String? = nil,
                tags: [String]? = nil) {
        self.priceAdjustPercent = priceAdjustPercent
        self.category = category
        self.tags = tags
    }

    enum CodingKeys: String, CodingKey {
        case category, tags
        case priceAdjustPercent = "price_adjust_percent"
    }
}

/// Request body for `POST /api/v1/inventory/items/batch`.
public struct BatchInventoryRequest: Encodable, Sendable {
    public let ids: [Int64]
    public let updates: BatchInventoryUpdates

    public init(ids: [Int64], updates: BatchInventoryUpdates) {
        self.ids = ids
        self.updates = updates
    }
}

/// Minimal response from the batch endpoint.
public struct BatchInventoryResponse: Decodable, Sendable {
    /// How many rows were actually modified.
    public let updatedCount: Int

    public init(updatedCount: Int) { self.updatedCount = updatedCount }

    enum CodingKeys: String, CodingKey {
        case updatedCount = "updated_count"
    }
}

// MARK: - SKU search DTOs

/// One result entry from the SKU search endpoint.
public struct SkuSearchResult: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let sku: String
    public let name: String?
    public let inStock: Int?
    public let retailPrice: Double?

    public var displayName: String { name ?? sku }

    public init(id: Int64, sku: String, name: String? = nil,
                inStock: Int? = nil, retailPrice: Double? = nil) {
        self.id = id
        self.sku = sku
        self.name = name
        self.inStock = inStock
        self.retailPrice = retailPrice
    }

    enum CodingKeys: String, CodingKey {
        case id, sku, name
        case inStock     = "in_stock"
        case retailPrice = "retail_price"
    }
}

// MARK: - APIClient extension

public extension APIClient {
    /// `POST /api/v1/inventory/items/batch`
    func batchUpdateInventory(_ req: BatchInventoryRequest) async throws -> BatchInventoryResponse {
        try await post("/api/v1/inventory/items/batch",
                       body: req, as: BatchInventoryResponse.self)
    }

    /// §6.1 Bulk delete — `POST /api/v1/inventory/items/batch-delete` with id list.
    /// Uses POST (not DELETE) because the standard `APIClient.delete(_:)` does not
    /// accept a request body. Server endpoint: POST /inventory/items/batch-delete { ids }.
    func batchDeleteInventory(_ req: BatchInventoryRequest) async throws -> BatchInventoryResponse {
        try await post("/api/v1/inventory/items/batch-delete",
                       body: req, as: BatchInventoryResponse.self)
    }

    // MARK: - §6.1 Import CSV/JSON

    /// `POST /api/v1/inventory/import-csv` — send raw CSV body.
    /// Server returns `{ success, data: { imported, errors: [{row, message}] } }`.
    @discardableResult
    func importInventoryCSV(_ request: InventoryImportCSVRequest) async throws -> InventoryImportResult {
        try await post("/api/v1/inventory/import-csv",
                       body: request,
                       as: InventoryImportResult.self)
    }

    /// `GET /api/v1/inventory` scoped to keyword search — reuses the list
    /// endpoint with a `keyword` query and a small page size for picker use.
    func searchSkus(keyword: String, limit: Int = 20) async throws -> [SkuSearchResult] {
        let query = [
            URLQueryItem(name: "keyword", value: keyword),
            URLQueryItem(name: "pagesize", value: String(limit))
        ]
        // The list endpoint returns InventoryListResponse; we map to SkuSearchResult shape.
        // SkuSearchResult mirrors the same fields from InventoryListItem.
        let resp = try await get("/api/v1/inventory", query: query,
                                 as: InventoryListResponse.self)
        return resp.items.map { item in
            SkuSearchResult(id: item.id, sku: item.sku ?? "",
                            name: item.name, inStock: item.inStock,
                            retailPrice: item.retailPrice)
        }
    }
}
