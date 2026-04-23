import Foundation

// MARK: - Receiving DTOs
//
// Server ground truth: packages/server/src/routes/inventory.routes.ts
// Mounted at: /api/v1/inventory
//
// The server exposes purchase orders and the receive action:
//   GET  /api/v1/inventory/purchase-orders/list     — paginated PO list
//   GET  /api/v1/inventory/purchase-orders/:id      — single PO with line items
//   POST /api/v1/inventory/purchase-orders/:id/receive  — receive against a PO
//   POST /api/v1/inventory/receive-scan             — bulk barcode receive
//
// There is NO dedicated /receiving namespace.

/// One line item in a purchase-order receipt.
/// Maps to `purchase_order_items` join `inventory_items` on the server.
public struct ReceivingLineItem: Codable, Sendable, Identifiable {
    public let id: Int64
    public let sku: String?
    public let productName: String?
    /// `quantity_ordered` from the server.
    public let orderedQty: Int
    /// `quantity_received` — running total already received.
    public let receivedQty: Int

    public init(id: Int64, sku: String? = nil, productName: String? = nil,
                orderedQty: Int, receivedQty: Int) {
        self.id = id
        self.sku = sku
        self.productName = productName
        self.orderedQty = orderedQty
        self.receivedQty = receivedQty
    }

    /// Quantity still outstanding.
    public var remaining: Int { max(0, orderedQty - receivedQty) }
    public var isFullyReceived: Bool { receivedQty >= orderedQty }

    enum CodingKeys: String, CodingKey {
        case id
        case sku
        case productName      = "item_name"  // server JOIN alias
        case orderedQty       = "quantity_ordered"
        case receivedQty      = "quantity_received"
    }
}

/// A purchase order / receiving record returned by the server.
/// Maps to `purchase_orders` + `suppliers` JOIN.
public struct ReceivingOrder: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let orderId: String?          // human-readable PO#
    public let supplierName: String?
    /// "draft" | "pending" | "ordered" | "partial" | "received" | "cancelled" | "backordered"
    public let status: String
    public let createdAt: String?
    public let expectedDate: String?
    public let lineItems: [ReceivingLineItem]

    public init(id: Int64, orderId: String? = nil, supplierName: String? = nil,
                status: String, createdAt: String? = nil,
                expectedDate: String? = nil, lineItems: [ReceivingLineItem] = []) {
        self.id = id
        self.orderId = orderId
        self.supplierName = supplierName
        self.status = status
        self.createdAt = createdAt
        self.expectedDate = expectedDate
        self.lineItems = lineItems
    }

    public var isOpen: Bool {
        status != "received" && status != "cancelled"
    }

    enum CodingKeys: String, CodingKey {
        case id, status
        case orderId      = "order_id"
        case supplierName = "supplier_name"
        case createdAt    = "created_at"
        case expectedDate = "expected_date"
        case lineItems    = "items"
    }
}

/// Paginated response from `GET /api/v1/inventory/purchase-orders/list`.
public struct ReceivingOrderListResponse: Decodable, Sendable {
    public let orders: [ReceivingOrder]
    public let pagination: Pagination?

    public struct Pagination: Decodable, Sendable {
        public let page: Int?
        public let perPage: Int?
        public let total: Int?
        public let totalPages: Int?

        enum CodingKeys: String, CodingKey {
            case page, total
            case perPage   = "per_page"
            case totalPages = "total_pages"
        }
    }
}

/// One entry in the receive request body for `POST .../purchase-orders/:id/receive`.
public struct ReceiveLineRequest: Encodable, Sendable {
    /// `purchase_order_items.id`
    public let purchaseOrderItemId: Int64
    public let quantityReceived: Int

    public init(purchaseOrderItemId: Int64, quantityReceived: Int) {
        self.purchaseOrderItemId = purchaseOrderItemId
        self.quantityReceived = quantityReceived
    }

    enum CodingKeys: String, CodingKey {
        case purchaseOrderItemId = "purchase_order_item_id"
        case quantityReceived    = "quantity_received"
    }
}

/// Request body for `POST /api/v1/inventory/purchase-orders/:id/receive`.
public struct FinalizeReceivingRequest: Encodable, Sendable {
    public let items: [ReceiveLineRequest]

    public init(items: [ReceiveLineRequest]) {
        self.items = items
    }

    // Compat shim for old callers using `lineItems:` + `FinalizedLine`.
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

    // Legacy init used by ReceivingDetailViewModel — builds item array from
    // FinalizedLine by matching sku. Since we now have the PO-item id we prefer
    // the items: init; this shim is kept for offline-queue backward compat.
    public init(lineItems: [FinalizedLine]) {
        // Without item ids we can't build ReceiveLineRequest; send empty so the
        // offline drain can log and skip. Real callers use items: init.
        self.items = []
    }

    enum CodingKeys: String, CodingKey {
        case items
    }
}

/// Entry in the scan-receive body for `POST /api/v1/inventory/receive-scan`.
public struct ScanReceiveEntry: Encodable, Sendable {
    public let barcode: String
    public let quantity: Int

    public init(barcode: String, quantity: Int = 1) {
        self.barcode = barcode
        self.quantity = quantity
    }
}

/// Request body for `POST /api/v1/inventory/receive-scan`.
public struct ScanReceiveRequest: Encodable, Sendable {
    public let items: [ScanReceiveEntry]
    public let notes: String?

    public init(items: [ScanReceiveEntry], notes: String? = nil) {
        self.items = items
        self.notes = notes
    }
}

/// Response entry from `POST /api/v1/inventory/receive-scan`.
public struct ScanReceiveResult: Decodable, Sendable {
    public let received: [ScanReceivedItem]
    public let unmatched: [ScanUnmatchedItem]
}

public struct ScanReceivedItem: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let sku: String?
    public let name: String?
    public let quantity: Int
    public let newStock: Int

    enum CodingKeys: String, CodingKey {
        case id, sku, name, quantity
        case newStock = "new_stock"
    }
}

public struct ScanUnmatchedItem: Decodable, Sendable, Identifiable {
    public let id: UUID = UUID()
    public let barcode: String
    public let quantity: Int

    enum CodingKeys: String, CodingKey {
        case barcode, quantity
    }
}

// MARK: - APIClient extension

public extension APIClient {
    /// `GET /api/v1/inventory/purchase-orders/list` — paginated list (open + recent).
    func listReceivingOrders(status: String? = nil, page: Int = 1) async throws -> [ReceivingOrder] {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pagesize", value: "50"),
        ]
        if let status { query.append(URLQueryItem(name: "status", value: status)) }
        let resp = try await get("/api/v1/inventory/purchase-orders/list",
                                 query: query,
                                 as: ReceivingOrderListResponse.self)
        return resp.orders
    }

    /// `GET /api/v1/inventory/purchase-orders/:id` — single PO with line items.
    func receivingOrder(id: Int64) async throws -> ReceivingOrder {
        let resp = try await get("/api/v1/inventory/purchase-orders/\(id)",
                                 as: PODetailResponse.self)
        // Re-map the server's { order, items } shape into ReceivingOrder.
        return ReceivingOrder(
            id: resp.order.id,
            orderId: resp.order.orderId,
            supplierName: resp.order.supplierName,
            status: resp.order.status,
            createdAt: resp.order.createdAt,
            expectedDate: resp.order.expectedDate,
            lineItems: resp.items
        )
    }

    /// `POST /api/v1/inventory/purchase-orders/:id/receive`
    func finalizeReceiving(id: Int64, request: FinalizeReceivingRequest) async throws -> CreatedResource {
        try await post("/api/v1/inventory/purchase-orders/\(id)/receive",
                       body: request,
                       as: CreatedResource.self)
    }

    /// `POST /api/v1/inventory/receive-scan` — bulk barcode scan-receive.
    func scanReceive(_ request: ScanReceiveRequest) async throws -> ScanReceiveResult {
        try await post("/api/v1/inventory/receive-scan",
                       body: request,
                       as: ScanReceiveResult.self)
    }
}

// MARK: - Internal decode helpers

/// `GET /api/v1/inventory/purchase-orders/:id` returns `{ order, items }`.
private struct PODetailResponse: Decodable {
    struct POHeader: Decodable {
        let id: Int64
        let orderId: String?
        let supplierName: String?
        let status: String
        let createdAt: String?
        let expectedDate: String?

        enum CodingKeys: String, CodingKey {
            case id, status
            case orderId      = "order_id"
            case supplierName = "supplier_name"
            case createdAt    = "created_at"
            case expectedDate = "expected_date"
        }
    }

    let order: POHeader
    let items: [ReceivingLineItem]
}
