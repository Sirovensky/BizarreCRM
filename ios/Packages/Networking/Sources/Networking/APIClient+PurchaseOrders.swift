import Foundation

// MARK: - §58 Purchase Orders — Networking-layer APIClient extensions
//
// Server: packages/server/src/routes/inventory.routes.ts
// Mounted at: /api/v1/inventory (index.ts:1538)
//
// Status transitions (ENR-INV6):
//   draft → pending (approve)  PUT /purchase-orders/:id  { status: "pending" }
//   pending → ordered          PUT /purchase-orders/:id  { status: "ordered" }
//   * → cancelled              PUT /purchase-orders/:id  { status: "cancelled" }
//   No DELETE endpoint — cancellation is a status transition.
//
// Read / receive endpoints already live in:
//   Endpoints/InventoryReceivingEndpoints.swift — ReceivingOrder / listReceivingOrders / receivingOrder / finalizeReceiving
//
// This file adds the write-side (create, update metadata, approve, cancel).
// The Inventory package's PurchaseOrderEndpoints.swift extends APIClient as well;
// these two extensions cover different method names and do not conflict.

// MARK: - DTOs

/// Minimal PO summary returned from create/update/status-transition calls.
/// Full detail (with line items) comes from ReceivingOrder (InventoryReceivingEndpoints.swift).
public struct POSummary: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let supplierId: Int64
    /// "draft" | "pending" | "ordered" | "backordered" | "partial" | "received" | "cancelled"
    public let status: String
    public let totalCents: Int
    public let notes: String?
    public let createdAt: String?
    public let expectedDate: String?

    public init(
        id: Int64,
        supplierId: Int64,
        status: String,
        totalCents: Int,
        notes: String? = nil,
        createdAt: String? = nil,
        expectedDate: String? = nil
    ) {
        self.id = id
        self.supplierId = supplierId
        self.status = status
        self.totalCents = totalCents
        self.notes = notes
        self.createdAt = createdAt
        self.expectedDate = expectedDate
    }

    public var isOpen: Bool {
        status != "received" && status != "cancelled"
    }

    enum CodingKeys: String, CodingKey {
        case id, status, notes
        case supplierId   = "supplier_id"
        case totalCents   = "total_cents"
        case createdAt    = "created_at"
        case expectedDate = "expected_date"
    }
}

/// Request body for creating a new PO.
public struct POCreateRequest: Encodable, Sendable {
    public let supplierId: Int64
    public let expectedDate: String?
    public let notes: String?
    public let items: [POCreateLineItem]

    public init(
        supplierId: Int64,
        expectedDate: String? = nil,
        notes: String? = nil,
        items: [POCreateLineItem]
    ) {
        self.supplierId = supplierId
        self.expectedDate = expectedDate
        self.notes = notes
        self.items = items
    }

    enum CodingKeys: String, CodingKey {
        case supplierId   = "supplier_id"
        case expectedDate = "expected_date"
        case notes, items
    }
}

/// One line in a POCreateRequest.
public struct POCreateLineItem: Encodable, Sendable {
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
        case sku, name
        case qtyOrdered    = "qty_ordered"
        case unitCostCents = "unit_cost_cents"
    }
}

/// Request body for updating PO metadata (notes / expected date).
public struct POUpdateRequest: Encodable, Sendable {
    public let expectedDate: String?
    public let notes: String?

    public init(expectedDate: String? = nil, notes: String? = nil) {
        self.expectedDate = expectedDate
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case expectedDate = "expected_date"
        case notes
    }
}

/// Request body for PUT status transitions (approve, cancel, etc.)
public struct POStatusRequest: Encodable, Sendable {
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

// MARK: - APIClient extension

public extension APIClient {

    /// `POST /api/v1/inventory/purchase-orders` — create a new draft PO.
    /// Requires `inventory.create` permission (SEC-H25).
    func createPO(_ body: POCreateRequest) async throws -> POSummary {
        try await post("/api/v1/inventory/purchase-orders", body: body, as: POSummary.self)
    }

    /// `PUT /api/v1/inventory/purchase-orders/:id` — update metadata (notes, expected date).
    /// Requires `inventory.edit` permission (SEC-H25).
    func updatePOMetadata(id: Int64, _ body: POUpdateRequest) async throws -> POSummary {
        try await put("/api/v1/inventory/purchase-orders/\(id)", body: body, as: POSummary.self)
    }

    /// `PUT /api/v1/inventory/purchase-orders/:id` — approve a draft PO (draft → pending).
    /// Requires `inventory.edit` permission (SEC-H25).
    func approvePO(id: Int64) async throws -> POSummary {
        let body = POStatusRequest(status: "pending")
        return try await put("/api/v1/inventory/purchase-orders/\(id)", body: body, as: POSummary.self)
    }

    /// `PUT /api/v1/inventory/purchase-orders/:id` — cancel an open PO (any non-terminal → cancelled).
    /// Requires `inventory.edit` permission (SEC-H25).
    func cancelPO(id: Int64, reason: String? = nil) async throws -> POSummary {
        let body = POStatusRequest(status: "cancelled", cancelledReason: reason)
        return try await put("/api/v1/inventory/purchase-orders/\(id)", body: body, as: POSummary.self)
    }
}
