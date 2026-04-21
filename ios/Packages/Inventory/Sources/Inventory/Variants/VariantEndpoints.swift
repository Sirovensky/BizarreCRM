import Foundation
import Networking

// MARK: - §6.10 Variant DTOs

public struct VariantListResponse: Decodable, Sendable {
    public let variants: [InventoryVariant]
}

public struct CreateVariantRequest: Encodable, Sendable {
    public let parentSKU: String
    public let attributes: [String: String]
    public let sku: String
    public let stock: Int
    public let retailCents: Int
    public let costCents: Int
    public let imageURL: String?

    public init(
        parentSKU: String,
        attributes: [String: String],
        sku: String,
        stock: Int,
        retailCents: Int,
        costCents: Int,
        imageURL: String? = nil
    ) {
        self.parentSKU = parentSKU
        self.attributes = attributes
        self.sku = sku
        self.stock = stock
        self.retailCents = retailCents
        self.costCents = costCents
        self.imageURL = imageURL
    }

    enum CodingKeys: String, CodingKey {
        case parentSKU   = "parent_sku"
        case attributes
        case sku
        case stock
        case retailCents = "retail_cents"
        case costCents   = "cost_cents"
        case imageURL    = "image_url"
    }
}

public struct UpdateVariantRequest: Encodable, Sendable {
    public let attributes: [String: String]?
    public let stock: Int?
    public let retailCents: Int?
    public let costCents: Int?
    public let imageURL: String?

    public init(
        attributes: [String: String]? = nil,
        stock: Int? = nil,
        retailCents: Int? = nil,
        costCents: Int? = nil,
        imageURL: String? = nil
    ) {
        self.attributes = attributes
        self.stock = stock
        self.retailCents = retailCents
        self.costCents = costCents
        self.imageURL = imageURL
    }

    enum CodingKeys: String, CodingKey {
        case attributes
        case stock
        case retailCents = "retail_cents"
        case costCents   = "cost_cents"
        case imageURL    = "image_url"
    }
}

// MARK: - APIClient extension

public extension APIClient {

    /// GET /api/v1/inventory/variants?parent_sku=<sku>
    func listVariants(parentSKU: String) async throws -> [InventoryVariant] {
        let query = [URLQueryItem(name: "parent_sku", value: parentSKU)]
        return try await get("/api/v1/inventory/variants", query: query, as: VariantListResponse.self).variants
    }

    /// POST /api/v1/inventory/variants
    func createVariant(_ request: CreateVariantRequest) async throws -> InventoryVariant {
        try await post("/api/v1/inventory/variants", body: request, as: InventoryVariant.self)
    }

    /// PUT /api/v1/inventory/variants/:id
    func updateVariant(id: Int64, request: UpdateVariantRequest) async throws -> InventoryVariant {
        try await put("/api/v1/inventory/variants/\(id)", body: request, as: InventoryVariant.self)
    }

    /// DELETE /api/v1/inventory/variants/:id
    func deleteVariant(id: Int64) async throws {
        try await delete("/api/v1/inventory/variants/\(id)")
    }
}
