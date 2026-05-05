import Foundation

// MARK: - POLineItem

/// A single line on a Purchase Order. All money in cents.
public struct POLineItem: Codable, Sendable, Identifiable {
    public let id: Int64
    public let sku: String
    public let name: String
    public let qtyOrdered: Int
    public let qtyReceived: Int
    public let unitCostCents: Int
    public let lineTotalCents: Int

    public init(
        id: Int64,
        sku: String,
        name: String,
        qtyOrdered: Int,
        qtyReceived: Int,
        unitCostCents: Int,
        lineTotalCents: Int
    ) {
        self.id = id
        self.sku = sku
        self.name = name
        self.qtyOrdered = qtyOrdered
        self.qtyReceived = qtyReceived
        self.unitCostCents = unitCostCents
        self.lineTotalCents = lineTotalCents
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sku
        case name
        case qtyOrdered     = "qty_ordered"
        case qtyReceived    = "qty_received"
        case unitCostCents  = "unit_cost_cents"
        case lineTotalCents = "line_total_cents"
    }
}
