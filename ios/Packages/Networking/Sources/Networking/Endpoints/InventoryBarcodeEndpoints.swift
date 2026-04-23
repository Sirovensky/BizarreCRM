import Foundation

// MARK: - Barcode lookup DTOs

/// Result for `GET /api/v1/inventory/barcode/:code`.
///
/// Server: packages/server/src/routes/inventory.routes.ts:548.
/// Matches the full `inventory_items` row for a single item.
/// `404` when not found — caller catches `APITransportError.httpStatus(404, _)`.
public struct InventoryBarcodeItem: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let name: String?
    public let sku: String?
    public let upc: String?
    public let inStock: Int?
    public let reorderLevel: Int?
    public let retailPrice: Double?
    public let costPrice: Double?
    public let itemType: String?
    public let category: String?
    public let isSerialized: Int?
    public let imageUrl: String?

    public var displayName: String { name?.isEmpty == false ? name! : "Unnamed" }

    enum CodingKeys: String, CodingKey {
        case id, name, sku, upc, category
        case inStock = "in_stock"
        case reorderLevel = "reorder_level"
        case retailPrice = "retail_price"
        case costPrice = "cost_price"
        case itemType = "item_type"
        case isSerialized = "is_serialized"
        case imageUrl = "image_url"
    }
}

// MARK: - APIClient extension

public extension APIClient {
    /// `GET /api/v1/inventory/barcode/:code`
    ///
    /// Looks up an inventory item by its SKU or UPC barcode.
    /// Throws `APITransportError.httpStatus(404, _)` when no active item matches.
    func inventoryItemByBarcode(_ code: String) async throws -> InventoryBarcodeItem {
        let encoded = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? code
        return try await get("/api/v1/inventory/barcode/\(encoded)", as: InventoryBarcodeItem.self)
    }
}
