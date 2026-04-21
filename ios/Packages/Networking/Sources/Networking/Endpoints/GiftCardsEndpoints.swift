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
}
