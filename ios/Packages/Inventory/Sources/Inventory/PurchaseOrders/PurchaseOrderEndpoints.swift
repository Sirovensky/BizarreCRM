import Foundation
import Networking

// MARK: - APIClient + PurchaseOrder endpoints
//
// Server: GET/POST/PUT routes live under /api/v1/inventory/purchase-orders
// (router mounted at /api/v1/inventory — see packages/server/src/index.ts:1538)
// List endpoint is /purchase-orders/list (paginated).
// There is NO DELETE endpoint; cancellation is a PUT with status = "cancelled".
// Approval (draft → pending) is a PUT with status = "pending".

public extension APIClient {

    // MARK: List

    func listPurchaseOrders(status: String? = nil) async throws -> [PurchaseOrder] {
        var query: [URLQueryItem] = []
        if let status { query.append(URLQueryItem(name: "status", value: status)) }
        return try await get("/api/v1/inventory/purchase-orders/list", query: query, as: [PurchaseOrder].self)
    }

    // MARK: Single PO

    func getPurchaseOrder(id: Int64) async throws -> PurchaseOrder {
        try await get("/api/v1/inventory/purchase-orders/\(id)", as: PurchaseOrder.self)
    }

    // MARK: Create

    func createPurchaseOrder(_ body: CreatePurchaseOrderRequest) async throws -> PurchaseOrder {
        try await post("/api/v1/inventory/purchase-orders", body: body, as: PurchaseOrder.self)
    }

    // MARK: Update (notes / expected date)

    func updatePurchaseOrder(id: Int64, _ body: UpdatePurchaseOrderRequest) async throws -> PurchaseOrder {
        try await put("/api/v1/inventory/purchase-orders/\(id)", body: body, as: PurchaseOrder.self)
    }

    // MARK: Status transitions

    /// Approve a draft PO (draft → pending). Uses PUT with status transition.
    func approvePurchaseOrder(id: Int64) async throws -> PurchaseOrder {
        let body = POStatusTransitionRequest(status: "pending")
        return try await put("/api/v1/inventory/purchase-orders/\(id)", body: body, as: PurchaseOrder.self)
    }

    /// Cancel a PO (any non-terminal status → cancelled). Uses PUT with status transition.
    func cancelPurchaseOrder(id: Int64, reason: String? = nil) async throws -> PurchaseOrder {
        let body = POStatusTransitionRequest(status: "cancelled", cancelledReason: reason)
        return try await put("/api/v1/inventory/purchase-orders/\(id)", body: body, as: PurchaseOrder.self)
    }

    // MARK: Receive

    func receivePurchaseOrder(id: Int64, _ body: ReceivePORequest) async throws -> PurchaseOrder {
        try await post("/api/v1/inventory/purchase-orders/\(id)/receive", body: body, as: PurchaseOrder.self)
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

/// Used for status transitions (approve, cancel). Separate from UpdatePurchaseOrderRequest
/// so that ordinary metadata edits cannot accidentally trigger a state machine change.
public struct POStatusTransitionRequest: Encodable, Sendable {
    public let status: String
    public let cancelledReason: String?

    public init(status: String, cancelledReason: String? = nil) {
        self.status = status
        self.cancelledReason = cancelledReason
    }

    enum CodingKeys: String, CodingKey {
        case status
        case cancelledReason = "cancelled_reason"
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
