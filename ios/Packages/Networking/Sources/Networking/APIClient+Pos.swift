import Foundation

/// POS held-carts DTOs + APIClient wrappers.
///
/// Server route: `POST /api/v1/pos/held-carts`  — save a cart.
///               `GET  /api/v1/pos/held-carts`  — list open carts.
///               `GET  /api/v1/pos/held-carts/:id` — single cart.
///               `POST /api/v1/pos/held-carts/:id/recall` — restore cart.
///               `DELETE /api/v1/pos/held-carts/:id` — soft-delete (discard).
///
/// Server envelope: `{ success: Bool, data: T?, message: String? }`.
/// All DTOs mirror the `held_carts` table columns the server returns.

// File-private empty body (POST with no payload).
private struct PosEmptyBody: Encodable, Sendable {}

// MARK: - Held-cart DTOs

/// Row returned by `GET /pos/held-carts` and `POST /pos/held-carts`.
/// `cart_json` is the raw JSON string the server persists — the iOS client
/// serialises its own `Cart` into this field and deserialises it on recall.
public struct PosHeldCartRow: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let userId: Int64
    public let workstationId: Int64?
    public let label: String?
    /// JSON string — parsed by the caller into a `CartSnapshot`.
    public let cartJson: String
    public let customerId: Int64?
    /// Total in cents (optional — may be nil on legacy rows).
    public let totalCents: Int?
    public let createdAt: String
    public let recalledAt: String?
    public let discardedAt: String?
    /// Only present on list responses when ?owner_name query flag is set.
    public let ownerFirstName: String?
    public let ownerLastName: String?

    public init(
        id: Int64,
        userId: Int64,
        workstationId: Int64? = nil,
        label: String? = nil,
        cartJson: String,
        customerId: Int64? = nil,
        totalCents: Int? = nil,
        createdAt: String,
        recalledAt: String? = nil,
        discardedAt: String? = nil,
        ownerFirstName: String? = nil,
        ownerLastName: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.workstationId = workstationId
        self.label = label
        self.cartJson = cartJson
        self.customerId = customerId
        self.totalCents = totalCents
        self.createdAt = createdAt
        self.recalledAt = recalledAt
        self.discardedAt = discardedAt
        self.ownerFirstName = ownerFirstName
        self.ownerLastName = ownerLastName
    }

    public var ownerName: String? {
        let parts = [ownerFirstName, ownerLastName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    public var displayLabel: String {
        label ?? "Hold #\(id)"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId          = "user_id"
        case workstationId   = "workstation_id"
        case label
        case cartJson        = "cart_json"
        case customerId      = "customer_id"
        case totalCents      = "total_cents"
        case createdAt       = "created_at"
        case recalledAt      = "recalled_at"
        case discardedAt     = "discarded_at"
        case ownerFirstName  = "owner_first_name"
        case ownerLastName   = "owner_last_name"
    }
}

/// Request body for `POST /pos/held-carts`.
public struct CreateHeldCartRequest: Encodable, Sendable {
    /// Serialised `CartSnapshot` (JSON string). Max 64 KB.
    public let cartJson: String
    public let label: String?
    public let workstationId: Int64?
    public let customerId: Int64?
    /// Total in cents — optional but surfaced in the list view.
    public let totalCents: Int?

    public init(
        cartJson: String,
        label: String? = nil,
        workstationId: Int64? = nil,
        customerId: Int64? = nil,
        totalCents: Int? = nil
    ) {
        self.cartJson = cartJson
        self.label = label
        self.workstationId = workstationId
        self.customerId = customerId
        self.totalCents = totalCents
    }

    enum CodingKeys: String, CodingKey {
        case cartJson        = "cart_json"
        case label
        case workstationId   = "workstation_id"
        case customerId      = "customer_id"
        case totalCents      = "total_cents"
    }
}

// MARK: - BlockChyp process-payment DTOs

/// Request body for `POST /api/v1/blockchyp/process-payment`.
public struct BlockChypPaymentRequest: Encodable, Sendable {
    public let invoiceId: Int64
    /// UUID used for idempotency. Must be a stable client-generated token.
    public let idempotencyKey: String
    /// Optional tip in dollars.
    public let tip: Double?

    public init(invoiceId: Int64, idempotencyKey: String, tip: Double? = nil) {
        self.invoiceId = invoiceId
        self.idempotencyKey = idempotencyKey
        self.tip = tip
    }

    enum CodingKeys: String, CodingKey {
        case invoiceId       = "invoiceId"
        case idempotencyKey  = "idempotency_key"
        case tip
    }
}

/// Response from `POST /api/v1/blockchyp/process-payment`.
public struct BlockChypPaymentResponse: Decodable, Sendable {
    public let success: Bool
    public let transactionId: String?
    public let transactionRef: String?
    public let cardType: String?
    public let last4: String?
    public let authCode: String?
    public let amount: Double?
    /// When non-nil the charge outcome is unknown — the operator must reconcile.
    public let status: String?
    public let replayed: Bool?

    public init(
        success: Bool,
        transactionId: String? = nil,
        transactionRef: String? = nil,
        cardType: String? = nil,
        last4: String? = nil,
        authCode: String? = nil,
        amount: Double? = nil,
        status: String? = nil,
        replayed: Bool? = nil
    ) {
        self.success = success
        self.transactionId = transactionId
        self.transactionRef = transactionRef
        self.cardType = cardType
        self.last4 = last4
        self.authCode = authCode
        self.amount = amount
        self.status = status
        self.replayed = replayed
    }

    public var isPendingReconciliation: Bool {
        status == "pending_reconciliation"
    }

    enum CodingKeys: String, CodingKey {
        case success, amount, status, replayed
        case transactionId  = "transactionId"
        case transactionRef = "transactionRef"
        case cardType       = "cardType"
        case last4          = "last4"
        case authCode       = "authCode"
    }
}

// MARK: - APIClient extensions

public extension APIClient {

    // MARK: Held carts

    /// `POST /api/v1/pos/held-carts` — save the current cart as a hold.
    func createHeldCart(_ request: CreateHeldCartRequest) async throws -> PosHeldCartRow {
        try await post("/api/v1/pos/held-carts", body: request, as: PosHeldCartRow.self)
    }

    /// `GET /api/v1/pos/held-carts` — list open (not recalled, not discarded) carts.
    func listHeldCarts() async throws -> [PosHeldCartRow] {
        try await get("/api/v1/pos/held-carts", as: [PosHeldCartRow].self)
    }

    /// `GET /api/v1/pos/held-carts/:id` — fetch a single held cart (with full cart_json).
    func getHeldCart(id: Int64) async throws -> PosHeldCartRow {
        try await get("/api/v1/pos/held-carts/\(id)", as: PosHeldCartRow.self)
    }

    /// `POST /api/v1/pos/held-carts/:id/recall` — mark recalled + return cart_json.
    /// After calling this the caller restores the cart from the returned row's `cartJson`.
    func recallHeldCart(id: Int64) async throws -> PosHeldCartRow {
        try await post("/api/v1/pos/held-carts/\(id)/recall", body: PosEmptyBody(), as: PosHeldCartRow.self)
    }

    /// `DELETE /api/v1/pos/held-carts/:id` — soft-delete (discard) a held cart.
    func discardHeldCart(id: Int64) async throws {
        try await delete("/api/v1/pos/held-carts/\(id)")
    }

    // MARK: BlockChyp terminal

    /// `POST /api/v1/blockchyp/process-payment` — charge a terminal for an invoice.
    /// Returns the full `BlockChypPaymentResponse` including `isPendingReconciliation`.
    func blockChypProcessPayment(_ request: BlockChypPaymentRequest) async throws -> BlockChypPaymentResponse {
        try await post("/api/v1/blockchyp/process-payment", body: request, as: BlockChypPaymentResponse.self)
    }
}
