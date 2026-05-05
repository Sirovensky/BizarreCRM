import Foundation

/// §40 — Gift card lookup + redeem wire formats, mapped to the endpoints
/// in `packages/server/src/routes/giftCards.routes.ts`:
///   - `GET  /api/v1/gift-cards/lookup/:code`
///   - `POST /api/v1/gift-cards/:id/redeem`
///
/// Server money is stored in dollars as `current_balance` / `amount` at
/// the DB layer. The iOS POS cart, every receipt path, and every Android
/// counterpart work exclusively in integer cents — `Double`-free money is
/// a hard constraint (`ios/CLAUDE.md`). We convert at this boundary:
/// server dollars → cents on the way in, cart cents → dollars on the way
/// out. The conversion keeps intermediate values in `Decimal` so the
/// rounding mode matches the `.bankers` policy used by `CartMath`.
///
/// We deliberately do NOT gatekeep on `status` / `expiresAt` here. The
/// server decides whether a card is redeemable and returns a typed 4xx
/// with a message. Swallowing that into "Card expired" UI locally would
/// hide a downgrade path (e.g. the server allows a one-time override for
/// a VIP). The sheet surfaces the status + expiry for the cashier to
/// eyeball, but Redeem always calls the server and lets it answer.

// MARK: - Lookup

/// Raw server payload for `GET /gift-cards/lookup/:code`. Dollars, so all
/// money fields are `Decimal` here — we convert to cents before leaving
/// this file via `GiftCard.init(from:)`.
struct GiftCardLookupRow: Decodable, Sendable {
    let id: Int64
    let code: String
    let currentBalance: Decimal?
    let initialBalance: Decimal?
    let status: String?
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case currentBalance = "current_balance"
        case initialBalance = "initial_balance"
        case status
        case expiresAt = "expires_at"
    }
}

/// Cart-side gift card projection. Cents-only, `active` derived from the
/// server's `status` string. `currency` is hardcoded USD until the server
/// adds multi-currency support — the field exists so the UI can already
/// read it and we only edit the mapping when the server catches up.
public struct GiftCard: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int64
    public let code: String
    public let balanceCents: Int
    public let currency: String
    public let expiresAt: String?
    public let active: Bool

    public init(
        id: Int64,
        code: String,
        balanceCents: Int,
        currency: String,
        expiresAt: String?,
        active: Bool
    ) {
        self.id = id
        self.code = code
        self.balanceCents = balanceCents
        self.currency = currency
        self.expiresAt = expiresAt
        self.active = active
    }

    /// Decode the raw row shape and convert dollars → cents. Using a
    /// single `init(from:)` lets `APIClient.get(...)` decode straight into
    /// this type — the call site never sees the dollars-world shape.
    public init(from decoder: Decoder) throws {
        let row = try GiftCardLookupRow(from: decoder)
        self.id = row.id
        self.code = row.code
        self.balanceCents = Self.dollarsToCents(row.currentBalance ?? 0)
        self.currency = "USD"
        self.expiresAt = row.expiresAt
        // Server returns `'active'` / `'used'` / `'disabled'`. Treat
        // absence as active so a legacy row without the field doesn't pin
        // the UI into a "disabled" state.
        self.active = (row.status ?? "active").lowercased() == "active"
    }

    /// Boundary helper. Keeps money in `Decimal` the entire way so we
    /// never touch `Double` for money. Mirrors `CartMath.toCents`
    /// semantics.
    static func dollarsToCents(_ decimal: Decimal) -> Int {
        var input = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .bankers)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    /// Reverse for redemption requests — cents leave the POS as dollars.
    static func centsToDollars(_ cents: Int) -> Decimal {
        Decimal(cents) / 100
    }
}

// MARK: - Redeem

/// Body for `POST /gift-cards/:id/redeem`. Server wants `amount` in
/// dollars as a decimal — we send a `Decimal` so no binary float ever
/// touches the wire.
public struct RedeemGiftCardRequest: Encodable, Sendable {
    public let amountCents: Int
    public let reason: String?

    public init(amountCents: Int, reason: String? = nil) {
        self.amountCents = amountCents
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case amount
        case reason
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(GiftCard.centsToDollars(amountCents), forKey: .amount)
        if let reason, !reason.isEmpty {
            try container.encode(reason, forKey: .reason)
        }
    }
}

/// Raw envelope from `/redeem` — dollars. Mapped to a cents-only shape
/// via the public `RedeemGiftCardResponse`.
struct GiftCardRedeemRow: Decodable, Sendable {
    let newBalance: Decimal?
    let status: String?
    let transactionId: Int64?

    enum CodingKeys: String, CodingKey {
        case newBalance = "new_balance"
        case status
        case transactionId = "transaction_id"
    }
}

public struct RedeemGiftCardResponse: Decodable, Sendable, Equatable {
    public let remainingBalanceCents: Int
    public let transactionId: Int64?

    public init(remainingBalanceCents: Int, transactionId: Int64?) {
        self.remainingBalanceCents = remainingBalanceCents
        self.transactionId = transactionId
    }

    public init(from decoder: Decoder) throws {
        let row = try GiftCardRedeemRow(from: decoder)
        self.remainingBalanceCents = GiftCard.dollarsToCents(row.newBalance ?? 0)
        self.transactionId = row.transactionId
    }
}

// MARK: - Sell / Activate

/// Body for `POST /gift-cards` — creates a new virtual gift card and sends
/// recipient email (+ optional SMS).
public struct CreateVirtualGiftCardRequest: Encodable, Sendable {
    public let recipientEmail: String
    public let recipientName: String
    public let amountCents: Int
    public let message: String?

    public init(
        recipientEmail: String,
        recipientName: String,
        amountCents: Int,
        message: String? = nil
    ) {
        self.recipientEmail = recipientEmail
        self.recipientName = recipientName
        self.amountCents = amountCents
        self.message = message
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case recipientEmail
        case recipientName
        case amountCents = "amount"
        case message
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("virtual", forKey: .kind)
        try c.encode(recipientEmail, forKey: .recipientEmail)
        try c.encode(recipientName, forKey: .recipientName)
        try c.encode(GiftCard.centsToDollars(amountCents), forKey: .amountCents)
        if let message, !message.isEmpty {
            try c.encode(message, forKey: .message)
        }
    }
}

/// Body for `POST /gift-cards/:id/activate` — activates a physical unissued card.
public struct ActivateGiftCardRequest: Encodable, Sendable {
    public let amountCents: Int
    public init(amountCents: Int) { self.amountCents = amountCents }
    enum CodingKeys: String, CodingKey { case amount }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(GiftCard.centsToDollars(amountCents), forKey: .amount)
    }
}

// MARK: - Reload

/// Body for `POST /gift-cards/:id/reload`.
public struct ReloadGiftCardRequest: Encodable, Sendable {
    public let amountCents: Int
    public init(amountCents: Int) { self.amountCents = amountCents }
    enum CodingKeys: String, CodingKey { case amount }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(GiftCard.centsToDollars(amountCents), forKey: .amount)
    }
}

/// Response from `/reload`.
public struct ReloadGiftCardResponse: Decodable, Sendable, Equatable {
    public let newBalanceCents: Int

    public init(newBalanceCents: Int) { self.newBalanceCents = newBalanceCents }

    public init(from decoder: Decoder) throws {
        struct Raw: Decodable {
            let newBalance: Decimal?
            enum CodingKeys: String, CodingKey { case newBalance = "new_balance" }
        }
        let raw = try Raw(from: decoder)
        newBalanceCents = GiftCard.dollarsToCents(raw.newBalance ?? 0)
    }
}

// MARK: - Transfer

/// Body for `POST /gift-cards/transfer`.
public struct TransferGiftCardRequest: Encodable, Sendable {
    public let sourceCardId: Int64
    public let targetCardId: Int64
    public let amountCents: Int

    public init(sourceCardId: Int64, targetCardId: Int64, amountCents: Int) {
        self.sourceCardId = sourceCardId
        self.targetCardId = targetCardId
        self.amountCents = amountCents
    }

    enum CodingKeys: String, CodingKey {
        case sourceCardId
        case targetCardId
        case amount
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sourceCardId, forKey: .sourceCardId)
        try c.encode(targetCardId, forKey: .targetCardId)
        try c.encode(GiftCard.centsToDollars(amountCents), forKey: .amount)
    }
}

/// Response from `/gift-cards/transfer`.
public struct TransferGiftCardResponse: Decodable, Sendable, Equatable {
    public let sourceBalanceCents: Int
    public let targetBalanceCents: Int

    public init(sourceBalanceCents: Int, targetBalanceCents: Int) {
        self.sourceBalanceCents = sourceBalanceCents
        self.targetBalanceCents = targetBalanceCents
    }

    public init(from decoder: Decoder) throws {
        struct Raw: Decodable {
            let sourceBalance: Decimal?
            let targetBalance: Decimal?
            enum CodingKeys: String, CodingKey {
                case sourceBalance = "source_balance"
                case targetBalance = "target_balance"
            }
        }
        let raw = try Raw(from: decoder)
        sourceBalanceCents = GiftCard.dollarsToCents(raw.sourceBalance ?? 0)
        targetBalanceCents = GiftCard.dollarsToCents(raw.targetBalance ?? 0)
    }
}

// MARK: - Store credit policy

public struct StoreCreditPolicyRequest: Encodable, Sendable {
    public enum ExpirationPeriod: String, Encodable, Sendable, CaseIterable {
        case days90 = "90"
        case days180 = "180"
        case days365 = "365"
        case never = "never"

        public var displayName: String {
            switch self {
            case .days90:  return "90 days"
            case .days180: return "180 days"
            case .days365: return "1 year"
            case .never:   return "Never"
            }
        }
    }

    public let expirationPeriod: ExpirationPeriod
    public init(expirationPeriod: ExpirationPeriod) { self.expirationPeriod = expirationPeriod }

    enum CodingKeys: String, CodingKey { case expirationPeriod = "expiration_period" }
}

// MARK: - Refund to gift card (extends invoice refund body)

/// Body for `POST /invoices/:id/refund` with gift-card issuance.
public struct InvoiceRefundRequest: Encodable, Sendable {
    public let amountCents: Int
    public let toGiftCard: Bool
    public let reason: String?

    public init(amountCents: Int, toGiftCard: Bool, reason: String? = nil) {
        self.amountCents = amountCents
        self.toGiftCard = toGiftCard
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case amount
        case toGiftCard
        case reason
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(GiftCard.centsToDollars(amountCents), forKey: .amount)
        try c.encode(toGiftCard, forKey: .toGiftCard)
        if let reason, !reason.isEmpty {
            try c.encode(reason, forKey: .reason)
        }
    }
}

/// Server response from invoice refund (includes optional new gift card when `toGiftCard: true`).
public struct InvoiceRefundResponse: Decodable, Sendable, Equatable {
    public let refundId: Int64?
    public let issuedGiftCard: GiftCard?

    public init(refundId: Int64?, issuedGiftCard: GiftCard?) {
        self.refundId = refundId
        self.issuedGiftCard = issuedGiftCard
    }

    enum CodingKeys: String, CodingKey {
        case refundId = "refund_id"
        case issuedGiftCard = "issued_gift_card"
    }
}

// MARK: - Client

public extension APIClient {
    /// Look up a gift card by its printed code. Server trims + uppercases
    /// on its side; we still trim client-side so trailing whitespace from
    /// a barcode scan never hits the rate limiter unnecessarily.
    func lookupGiftCard(code: String) async throws -> GiftCard {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        // URL-escape the raw code. A pasted code could in theory contain
        // characters that need percent-encoding; the server decodes
        // before hashing, so as long as we escape here the two paths
        // agree.
        let escaped = trimmed.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? trimmed
        return try await get("/api/v1/gift-cards/lookup/\(escaped)", as: GiftCard.self)
    }

    /// Redeem `amountCents` against the card. The server enforces the
    /// atomic decrement + expiry re-check so the client is a thin shell
    /// over the POST — no local balance-gating.
    func redeemGiftCard(
        id: Int64,
        amountCents: Int,
        reason: String? = nil
    ) async throws -> RedeemGiftCardResponse {
        let body = RedeemGiftCardRequest(amountCents: amountCents, reason: reason)
        return try await post(
            "/api/v1/gift-cards/\(id)/redeem",
            body: body,
            as: RedeemGiftCardResponse.self
        )
    }

    // MARK: - Sell

    /// Create a new virtual gift card. Server sends recipient email with
    /// code + QR. Returns the newly-created card.
    func createVirtualGiftCard(_ request: CreateVirtualGiftCardRequest) async throws -> GiftCard {
        return try await post("/api/v1/gift-cards", body: request, as: GiftCard.self)
    }

    /// Activate a physical unissued card (looked up by barcode scan first).
    func activateGiftCard(id: Int64, amountCents: Int) async throws -> GiftCard {
        let body = ActivateGiftCardRequest(amountCents: amountCents)
        return try await post(
            "/api/v1/gift-cards/\(id)/activate",
            body: body,
            as: GiftCard.self
        )
    }

    // MARK: - Reload

    /// Add funds to an existing active gift card.
    func reloadGiftCard(id: Int64, amountCents: Int) async throws -> ReloadGiftCardResponse {
        let body = ReloadGiftCardRequest(amountCents: amountCents)
        return try await post(
            "/api/v1/gift-cards/\(id)/reload",
            body: body,
            as: ReloadGiftCardResponse.self
        )
    }

    // MARK: - Transfer

    /// Move balance from one card to another. Server creates an audit entry automatically.
    func transferGiftCard(_ request: TransferGiftCardRequest) async throws -> TransferGiftCardResponse {
        return try await post(
            "/api/v1/gift-cards/transfer",
            body: request,
            as: TransferGiftCardResponse.self
        )
    }

    // MARK: - Store credit policy

    @discardableResult
    func updateStoreCreditPolicy(_ request: StoreCreditPolicyRequest) async throws -> EmptyResponse {
        return try await post("/api/v1/settings/store-credit-policy", body: request, as: EmptyResponse.self)
    }

    // MARK: - Refund to gift card

    func refundInvoice(id: Int64, request: InvoiceRefundRequest) async throws -> InvoiceRefundResponse {
        return try await post(
            "/api/v1/invoices/\(id)/refund",
            body: request,
            as: InvoiceRefundResponse.self
        )
    }
}

// MARK: - EmptyResponse helper

/// Placeholder response for endpoints that return an empty 204 body or a simple
/// `{ success: true }` envelope that carries no payload.
public struct EmptyResponse: Decodable, Sendable {
    public init() {}
}
