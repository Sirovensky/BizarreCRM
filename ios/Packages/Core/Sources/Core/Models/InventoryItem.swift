import Foundation

public struct InventoryItem: Identifiable, Hashable, Codable, Sendable {
    public let id: Int64
    public let sku: String
    public let name: String
    public let barcode: String?
    public let stockQty: Int
    public let reorderLevel: Int
    public let priceCents: Int
    public let costCents: Int
    public let updatedAt: Date

    public init(
        id: Int64,
        sku: String,
        name: String,
        barcode: String? = nil,
        stockQty: Int = 0,
        reorderLevel: Int = 0,
        priceCents: Int = 0,
        costCents: Int = 0,
        updatedAt: Date
    ) {
        self.id = id
        self.sku = sku
        self.name = name
        self.barcode = barcode
        self.stockQty = stockQty
        self.reorderLevel = reorderLevel
        self.priceCents = priceCents
        self.costCents = costCents
        self.updatedAt = updatedAt
    }

    public var isLowStock: Bool { stockQty <= reorderLevel }
}
