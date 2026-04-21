import Foundation
import Networking

// MARK: - §43.4 Part Mapping API Wrappers

public extension APIClient {

    /// Search inventory items by query string (for SKU picker).
    func searchInventoryItems(query: String) async throws -> [InventorySearchResult] {
        let q = [URLQueryItem(name: "q", value: query)]
        return try await get("/api/v1/inventory/items", query: q, as: [InventorySearchResult].self)
    }

    /// PATCH service with primary SKU + bundle assignment.
    @discardableResult
    func updateServiceParts(serviceId: Int64, body: UpdateServicePartsRequest) async throws -> RepairService {
        try await patch("/api/v1/repair-pricing/services/\(serviceId)", body: body, as: RepairService.self)
    }
}

// MARK: - Inventory search DTO (lightweight, lives here to avoid Core dep growth)

/// Minimal inventory item returned by `GET /inventory/items?q=...`
public struct InventorySearchResult: Identifiable, Decodable, Sendable, Hashable {
    public let id: Int64
    public let sku: String
    public let name: String
    public let stockQty: Int
    public let priceCents: Int

    public init(id: Int64, sku: String, name: String, stockQty: Int = 0, priceCents: Int = 0) {
        self.id = id
        self.sku = sku
        self.name = name
        self.stockQty = stockQty
        self.priceCents = priceCents
    }

    enum CodingKeys: String, CodingKey {
        case id, sku, name
        case stockQty   = "stock_qty"
        case priceCents = "price_cents"
    }
}
