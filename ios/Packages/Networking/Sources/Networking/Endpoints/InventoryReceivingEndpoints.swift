import Foundation

// MARK: - Receiving DTOs

/// One line item in a purchase-order receipt.
public struct ReceivingLineItem: Codable, Sendable, Identifiable {
    public let id: Int64
    public let sku: String
    public let productName: String?
    public let orderedQty: Int
    public let receivedQty: Int

    public init(id: Int64, sku: String, productName: String? = nil,
                orderedQty: Int, receivedQty: Int) {
        self.id = id
        self.sku = sku
        self.productName = productName
        self.orderedQty = orderedQty
        self.receivedQty = receivedQty
    }

    enum CodingKeys: String, CodingKey {
        case id, sku
        case productName  = "product_name"
        case orderedQty   = "ordered_qty"
        case receivedQty  = "received_qty"
    }
}

/// A purchase-order / receiving record returned by the server.
public struct ReceivingOrder: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let supplierName: String?
    public let status: String           // "open" | "partial" | "complete"
    public let createdAt: String?
    public let lineItems: [ReceivingLineItem]

    public init(id: Int64, supplierName: String? = nil, status: String,
                createdAt: String? = nil, lineItems: [ReceivingLineItem] = []) {
        self.id = id
        self.supplierName = supplierName
        self.status = status
        self.createdAt = createdAt
        self.lineItems = lineItems
    }

    enum CodingKeys: String, CodingKey {
        case id, status
        case supplierName = "supplier_name"
        case createdAt    = "created_at"
        case lineItems    = "line_items"
    }
}

/// Request body for `POST /api/v1/inventory/receiving/:id/finalize`.
public struct FinalizeReceivingRequest: Encodable, Sendable {
    public let lineItems: [FinalizedLine]

    public init(lineItems: [FinalizedLine]) {
        self.lineItems = lineItems
    }

    public struct FinalizedLine: Encodable, Sendable {
        public let sku: String
        public let quantityReceived: Int

        public init(sku: String, quantityReceived: Int) {
            self.sku = sku
            self.quantityReceived = quantityReceived
        }

        enum CodingKeys: String, CodingKey {
            case sku
            case quantityReceived = "quantity_received"
        }
    }

    enum CodingKeys: String, CodingKey {
        case lineItems = "line_items"
    }
}

// MARK: - APIClient extension

public extension APIClient {
    /// `GET /api/v1/inventory/receiving` — list of open purchase orders.
    func listReceivingOrders() async throws -> [ReceivingOrder] {
        try await get("/api/v1/inventory/receiving", as: [ReceivingOrder].self)
    }

    /// `GET /api/v1/inventory/receiving/:id` — single PO detail with line items.
    func receivingOrder(id: Int64) async throws -> ReceivingOrder {
        try await get("/api/v1/inventory/receiving/\(id)", as: ReceivingOrder.self)
    }

    /// `POST /api/v1/inventory/receiving/:id/finalize`
    func finalizeReceiving(id: Int64, request: FinalizeReceivingRequest) async throws -> CreatedResource {
        try await post("/api/v1/inventory/receiving/\(id)/finalize",
                       body: request, as: CreatedResource.self)
    }
}
