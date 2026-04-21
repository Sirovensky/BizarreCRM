import Foundation

// MARK: - §6.10 Inventory Variant

/// One variant of a parent inventory item (e.g. Red / Small / 128GB).
/// Each variant has its own SKU and stock level. All money in cents.
public struct InventoryVariant: Codable, Sendable, Identifiable, Hashable {
    public let id: Int64
    /// SKU of the parent inventory item.
    public let parentSKU: String
    /// Variant-specific attributes, e.g. ["color": "Red", "size": "Small"].
    public let attributes: [String: String]
    /// Unique SKU for this specific variant.
    public let sku: String
    public let stock: Int
    public let retailCents: Int
    public let costCents: Int
    public let imageURL: URL?

    public init(
        id: Int64,
        parentSKU: String,
        attributes: [String: String],
        sku: String,
        stock: Int,
        retailCents: Int,
        costCents: Int,
        imageURL: URL? = nil
    ) {
        self.id = id
        self.parentSKU = parentSKU
        self.attributes = attributes
        self.sku = sku
        self.stock = stock
        self.retailCents = retailCents
        self.costCents = costCents
        self.imageURL = imageURL
    }

    enum CodingKeys: String, CodingKey {
        case id
        case parentSKU    = "parent_sku"
        case attributes
        case sku
        case stock
        case retailCents  = "retail_cents"
        case costCents    = "cost_cents"
        case imageURL     = "image_url"
    }

    /// Human-readable label for accessibility and UI, e.g. "Red, Small".
    public var displayLabel: String {
        attributes.sorted(by: { $0.key < $1.key }).map(\.value).joined(separator: ", ")
    }
}
