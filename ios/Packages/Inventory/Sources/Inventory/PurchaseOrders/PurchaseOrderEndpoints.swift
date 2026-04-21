import Foundation
import Networking

// MARK: - APIClient + PurchaseOrder endpoints

public extension APIClient {

    func listPurchaseOrders(status: String? = nil) async throws -> [PurchaseOrder] {
        var query: [URLQueryItem] = []
        if let status { query.append(URLQueryItem(name: "status", value: status)) }
        return try await get("/api/v1/purchase-orders", query: query, as: [PurchaseOrder].self)
    }

    func getPurchaseOrder(id: Int64) async throws -> PurchaseOrder {
        try await get("/api/v1/purchase-orders/\(id)", as: PurchaseOrder.self)
    }

    func createPurchaseOrder(_ body: CreatePurchaseOrderRequest) async throws -> PurchaseOrder {
        try await post("/api/v1/purchase-orders", body: body, as: PurchaseOrder.self)
    }

    func updatePurchaseOrder(id: Int64, _ body: UpdatePurchaseOrderRequest) async throws -> PurchaseOrder {
        try await put("/api/v1/purchase-orders/\(id)", body: body, as: PurchaseOrder.self)
    }

    func receivePurchaseOrder(id: Int64, _ body: ReceivePORequest) async throws -> PurchaseOrder {
        try await post("/api/v1/purchase-orders/\(id)/receive", body: body, as: PurchaseOrder.self)
    }

    func cancelPurchaseOrder(id: Int64) async throws {
        try await delete("/api/v1/purchase-orders/\(id)")
    }
}

// MARK: - Request bodies

public struct CreatePurchaseOrderRequest: Encodable, Sendable {
    public let supplierId: Int64
    public let expectedDate: Date?
    public let items: [POLineItemRequest]
    public let notes: String?

    public init(supplierId: Int64, expectedDate: Date?, items: [POLineItemRequest], notes: String?) {
        self.supplierId = supplierId
        self.expectedDate = expectedDate
        self.items = items
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case supplierId   = "supplier_id"
        case expectedDate = "expected_date"
        case items
        case notes
    }
}

public struct UpdatePurchaseOrderRequest: Encodable, Sendable {
    public let expectedDate: Date?
    public let notes: String?

    public init(expectedDate: Date?, notes: String?) {
        self.expectedDate = expectedDate
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case expectedDate = "expected_date"
        case notes
    }
}

public struct POLineItemRequest: Encodable, Sendable {
    public let sku: String
    public let name: String
    public let qtyOrdered: Int
    public let unitCostCents: Int

    public init(sku: String, name: String, qtyOrdered: Int, unitCostCents: Int) {
        self.sku = sku
        self.name = name
        self.qtyOrdered = qtyOrdered
        self.unitCostCents = unitCostCents
    }

    enum CodingKeys: String, CodingKey {
        case sku
        case name
        case qtyOrdered    = "qty_ordered"
        case unitCostCents = "unit_cost_cents"
    }
}

public struct ReceivePORequest: Encodable, Sendable {
    public let lines: [ReceivePOLine]

    public init(lines: [ReceivePOLine]) { self.lines = lines }
}

public struct ReceivePOLine: Encodable, Sendable {
    public let lineItemId: Int64
    public let qtyReceived: Int

    public init(lineItemId: Int64, qtyReceived: Int) {
        self.lineItemId = lineItemId
        self.qtyReceived = qtyReceived
    }

    enum CodingKeys: String, CodingKey {
        case lineItemId  = "line_item_id"
        case qtyReceived = "qty_received"
    }
}
