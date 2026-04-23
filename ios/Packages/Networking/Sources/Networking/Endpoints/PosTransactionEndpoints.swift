import Foundation

/// §16.7 / §16.5 — POS transaction DTOs + APIClient wrappers.
///
/// Server route: `POST /api/v1/pos/transaction`
/// GET  route:   `GET  /api/v1/pos/products`
///
/// POS1: server forces unit_price from inventory_items.retail_price — the
/// client must NOT send a unit price; the server re-prices every line.
/// POS2: the entire write sequence is atomic on the server side.

// MARK: - Transaction DTOs

/// One line item sent to `POST /pos/transaction`.
public struct PosTransactionLineItem: Encodable, Sendable, Equatable {
    public let inventoryItemId: Int64
    public let quantity: Int
    /// Fractional dollar discount applied to this line only (e.g. 2.00 = $2 off).
    public let lineDiscount: Double?
    public let kitId: Int64?

    public init(
        inventoryItemId: Int64,
        quantity: Int,
        lineDiscount: Double? = nil,
        kitId: Int64? = nil
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

/// One leg of a split-payment array (field `payments`).
public struct PosPaymentLeg: Encodable, Sendable, Equatable {
    /// Must match a row in `payment_methods.name` that is `is_active = 1`.
    public let method: String
    /// Dollar amount (not cents).
    public let amount: Double
    public let processor: String?
    public let reference: String?
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
        case method
        case amount
        case processor
        case reference
        case transactionId = "transaction_id"
    }
}

/// Full request body for `POST /pos/transaction`.
public struct PosTransactionRequest: Encodable, Sendable {
    public let items: [PosTransactionLineItem]
    public let customerId: Int64?
    /// Cart-level discount in dollars (not per-line).
    public let discount: Double?
    /// Tip in dollars.
    public let tip: Double?
    public let notes: String?
    /// Single-payment path: method name matching `payment_methods.name`.
    public let paymentMethod: String?
    /// Single-payment path: dollar amount.
    public let paymentAmount: Double?
    /// Split-payment path: if present, `paymentMethod`/`paymentAmount` are ignored.
    public let payments: [PosPaymentLeg]?
    /// UUID string for idempotency. The server deduplicates on this key.
    public let idempotencyKey: String?

    public init(
        items: [PosTransactionLineItem],
        customerId: Int64? = nil,
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
        case items
        case customerId     = "customer_id"
        case discount
        case tip
        case notes
        case paymentMethod  = "payment_method"
        case paymentAmount  = "payment_amount"
        case payments
        case idempotencyKey = "idempotency_key"
    }
}

// MARK: - Transaction response

public struct PosTransactionInvoice: Decodable, Sendable {
    public let id: Int64
    public let orderId: String?
    public let totalCents: Int?
    /// Total as a decimal dollar string from the server.
    public let total: Double?

    public init(id: Int64, orderId: String? = nil, totalCents: Int? = nil, total: Double? = nil) {
        self.id = id
        self.orderId = orderId
        self.totalCents = totalCents
        self.total = total
    }

    enum CodingKeys: String, CodingKey {
        case id
        case orderId    = "order_id"
        case totalCents = "total_cents"
        case total
    }
}

public struct PosTransactionResponse: Decodable, Sendable {
    public let invoice: PosTransactionInvoice
    public let message: String?

    public init(invoice: PosTransactionInvoice, message: String? = nil) {
        self.invoice = invoice
        self.message = message
    }
}

// MARK: - Products DTOs

public struct PosProduct: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let name: String
    public let itemType: String?
    public let category: String?
    /// Dollar price from server. Use `priceCents` for display.
    public let retailPrice: Double?
    public let inStock: Int?
    public let sku: String?
    public let upc: String?
    public let imageUrl: String?
    public let taxClassId: Int64?
    public let taxInclusive: Bool?

    public var priceCents: Int? {
        guard let p = retailPrice else { return nil }
        return Int((p * 100).rounded())
    }

    public init(
        id: Int64,
        name: String,
        itemType: String? = nil,
        category: String? = nil,
        retailPrice: Double? = nil,
        inStock: Int? = nil,
        sku: String? = nil,
        upc: String? = nil,
        imageUrl: String? = nil,
        taxClassId: Int64? = nil,
        taxInclusive: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.itemType = itemType
        self.category = category
        self.retailPrice = retailPrice
        self.inStock = inStock
        self.sku = sku
        self.upc = upc
        self.imageUrl = imageUrl
        self.taxClassId = taxClassId
        self.taxInclusive = taxInclusive
    }

    enum CodingKeys: String, CodingKey {
        case id, name, sku, upc
        case itemType     = "item_type"
        case category
        case retailPrice  = "retail_price"
        case inStock      = "in_stock"
        case imageUrl     = "image_url"
        case taxClassId   = "tax_class_id"
        case taxInclusive = "tax_inclusive"
    }
}

public struct PosProductsResponse: Decodable, Sendable {
    public let items: [PosProduct]
    public let categories: [String]

    public init(items: [PosProduct], categories: [String]) {
        self.items = items
        self.categories = categories
    }
}

// MARK: - APIClient wrappers

public extension APIClient {
    /// POST a completed POS sale transaction to the server.
    func posTransaction(_ request: PosTransactionRequest) async throws -> PosTransactionResponse {
        try await post("/api/v1/pos/transaction", body: request, as: PosTransactionResponse.self)
    }

    /// GET the catalog for the POS search panel.
    func posProducts(
        keyword: String? = nil,
        category: String? = nil
    ) async throws -> PosProductsResponse {
        var query: [URLQueryItem] = []
        if let k = keyword, !k.isEmpty {
            query.append(URLQueryItem(name: "keyword", value: k))
        }
        if let c = category, !c.isEmpty {
            query.append(URLQueryItem(name: "category", value: c))
        }
        if query.isEmpty {
            return try await get("/api/v1/pos/products", as: PosProductsResponse.self)
        }
        return try await get("/api/v1/pos/products", query: query, as: PosProductsResponse.self)
    }
}
