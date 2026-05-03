import Foundation

// MARK: - Request DTOs

/// A single line item sent to `POST /api/v1/pos/transaction`.
/// Server: packages/server/src/routes/pos.routes.ts — `/pos/transaction`.
public struct PosTransactionLineItem: Encodable, Sendable {
    public let inventoryItemId: Int
    public let quantity: Int
    /// Optional per-line discount in dollars. Server validates against gross.
    public let lineDiscount: Double?
    /// Optional kit id when the line is a kit-sell.
    public let kitId: Int?

    public init(
        inventoryItemId: Int,
        quantity: Int,
        lineDiscount: Double? = nil,
        kitId: Int? = nil
    ) {
        self.inventoryItemId = inventoryItemId
        self.quantity = quantity
        self.lineDiscount = lineDiscount
        self.kitId = kitId
    }

    enum CodingKeys: String, CodingKey {
        case inventoryItemId = "inventory_item_id"
        case quantity
        case lineDiscount    = "line_discount"
        case kitId           = "kit_id"
    }
}

/// Single payment leg for the `payments` split-tender array.
public struct PosPaymentLeg: Encodable, Sendable {
    public let method: String
    public let amount: Double
    /// Optional processor name (BlockChyp, etc.).
    public let processor: String?
    /// Optional human reference string (auth code, check #, etc.).
    public let reference: String?
    /// Optional transaction id from the payment processor.
    public let transactionId: String?

    public init(
        method: String,
        amount: Double,
        processor: String? = nil,
        reference: String? = nil,
        transactionId: String? = nil
    ) {
        self.method = method
        self.amount = amount
        self.processor = processor
        self.reference = reference
        self.transactionId = transactionId
    }

    enum CodingKeys: String, CodingKey {
        case method, amount, processor, reference
        case transactionId = "transaction_id"
    }
}

/// Request body for `POST /api/v1/pos/transaction`.
/// POS1: server re-prices every line — we never send `unit_price`.
/// POS7: omit `customer_id` for walk-in; server creates/reuses sentinel.
public struct PosTransactionRequest: Encodable, Sendable {
    public let items: [PosTransactionLineItem]
    /// Optional customer id. Omit for walk-in (server uses WALK-IN sentinel).
    public let customerId: Int?
    /// Cart-level discount in dollars. Server validates and caps.
    public let discount: Double?
    /// Tip in dollars.
    public let tip: Double?
    /// Freeform notes.
    public let notes: String?
    /// Single-method payment (legacy). Mutually exclusive with `payments`.
    public let paymentMethod: String?
    /// Single-method amount in dollars. Used with `paymentMethod`.
    public let paymentAmount: Double?
    /// Split-tender array. Use instead of `paymentMethod`/`paymentAmount`.
    public let payments: [PosPaymentLeg]?
    /// Client-generated idempotency key. Required for safe retries.
    public let idempotencyKey: String?

    public init(
        items: [PosTransactionLineItem],
        customerId: Int? = nil,
        discount: Double? = nil,
        tip: Double? = nil,
        notes: String? = nil,
        paymentMethod: String? = nil,
        paymentAmount: Double? = nil,
        payments: [PosPaymentLeg]? = nil,
        idempotencyKey: String? = nil
    ) {
        self.items = items
        self.customerId = customerId
        self.discount = discount
        self.tip = tip
        self.notes = notes
        self.paymentMethod = paymentMethod
        self.paymentAmount = paymentAmount
        self.payments = payments
        self.idempotencyKey = idempotencyKey
    }

    enum CodingKeys: String, CodingKey {
        case items, discount, tip, notes, payments
        case customerId     = "customer_id"
        case paymentMethod  = "payment_method"
        case paymentAmount  = "payment_amount"
        case idempotencyKey = "idempotency_key"
    }
}

// MARK: - Response DTOs

/// Invoice row returned by a successful POS transaction.
public struct PosTransactionInvoice: Decodable, Sendable {
    public let id: Int64
    public let orderId: String?
    /// Optional cents total for test fixtures or future cents-based endpoints.
    /// `/pos/transaction` currently returns `total` in dollars, so callers
    /// should fall back to `total` when this is nil.
    public let totalCents: Int?
    public let total: Double?
    public let status: String?

    public init(
        id: Int64,
        orderId: String? = nil,
        totalCents: Int? = nil,
        total: Double? = nil,
        status: String? = nil
    ) {
        self.id = id
        self.orderId = orderId
        self.totalCents = totalCents
        self.total = total
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case id, total, status
        case orderId = "order_id"
        case totalCents = "total_cents"
    }
}

/// Successful response from `POST /api/v1/pos/transaction`.
public struct PosTransactionResponse: Decodable, Sendable {
    public let invoice: PosTransactionInvoice
    public let message: String?

    enum CodingKeys: String, CodingKey {
        case invoice, message
    }
}

// MARK: - APIClient extension

public extension APIClient {
    /// Submit a completed POS sale to the server.
    ///
    /// The server re-prices every inventory line (POS1), applies membership
    /// discounts server-side (POS8), validates the payment total, and writes
    /// the invoice + payments + stock decrements atomically (POS2).
    ///
    /// Pass a fresh `UUID().uuidString` as `request.idempotencyKey` so the
    /// middleware deduplicates double-taps or network retries.
    func posTransaction(_ request: PosTransactionRequest) async throws -> PosTransactionResponse {
        try await post("/api/v1/pos/transaction", body: request, as: PosTransactionResponse.self)
    }

    /// Fetch available products for the POS catalog.
    /// Server: GET /api/v1/pos/products
    func posProducts(keyword: String? = nil, category: String? = nil) async throws -> PosProductsResponse {
        var path = "/api/v1/pos/products"
        var queryItems: [URLQueryItem] = []
        if let k = keyword, !k.isEmpty { queryItems.append(URLQueryItem(name: "keyword", value: k)) }
        if let c = category, !c.isEmpty { queryItems.append(URLQueryItem(name: "category", value: c)) }
        if !queryItems.isEmpty {
            let qs = queryItems.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
            path = "\(path)?\(qs)"
        }
        return try await get(path, as: PosProductsResponse.self)
    }
}

/// Response from `GET /api/v1/pos/products`.
public struct PosProductsResponse: Decodable, Sendable {
    public let items: [PosProduct]
    public let categories: [String]
}

/// A single product in the POS catalog.
public struct PosProduct: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let name: String
    public let itemType: String?
    public let category: String?
    /// Retail price in dollars.
    public let retailPrice: Double?
    public let inStock: Int?
    public let sku: String?
    public let upc: String?
    public let imageUrl: String?
    public let taxClassId: Int64?
    public let taxInclusive: Bool?

    /// Price in integer cents for `CartMath`.
    public var priceCents: Int? {
        guard let p = retailPrice else { return nil }
        return Int((p * 100).rounded())
    }

    public var displayName: String { name }

    public var hasStock: Bool { (inStock ?? 1) > 0 }

    enum CodingKeys: String, CodingKey {
        case id, name, sku, upc
        case itemType    = "item_type"
        case category
        case retailPrice = "retail_price"
        case inStock     = "in_stock"
        case imageUrl    = "image_url"
        case taxClassId  = "tax_class_id"
        case taxInclusive = "tax_inclusive"
    }
}
