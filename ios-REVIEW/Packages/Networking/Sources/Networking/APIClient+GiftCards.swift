import Foundation

/// §40 — Gift card issue + list endpoints, extending the core gift-cards
/// surface already defined in `GiftCardsEndpoints.swift`.
///
/// Routes confirmed against `packages/server/src/routes/giftCards.routes.ts`:
///   POST /api/v1/gift-cards          — issue a new card (admin/manager only)
///   GET  /api/v1/gift-cards          — list all cards (keyword, status, page)
///   GET  /api/v1/gift-cards/lookup/:code — lookup by code (already in GiftCardsEndpoints)
///   POST /api/v1/gift-cards/:id/redeem   — redeem as tender (already in GiftCardsEndpoints)
///
/// Store-credit list confirmed via `packages/server/src/routes/refunds.routes.ts`:
///   GET  /api/v1/refunds/credits/:customerId — balance + transaction history

// MARK: - Issue gift card

/// Request body for `POST /api/v1/gift-cards` from the manager issue path.
/// The existing `CreateVirtualGiftCardRequest` is for the POS "sell virtual"
/// flow (sends an email). This type issues a generic card — physical or virtual —
/// using the minimal server-required fields.
public struct IssueGiftCardRequest: Encodable, Sendable {
    /// Initial load amount in cents. Sent to server as dollars.
    public let amountCents: Int
    public let customerId: Int64?
    public let recipientName: String?
    public let recipientEmail: String?
    public let expiresAt: String?
    public let notes: String?

    public init(
        amountCents: Int,
        customerId: Int64? = nil,
        recipientName: String? = nil,
        recipientEmail: String? = nil,
        expiresAt: String? = nil,
        notes: String? = nil
    ) {
        self.amountCents = amountCents
        self.customerId = customerId
        self.recipientName = recipientName
        self.recipientEmail = recipientEmail
        self.expiresAt = expiresAt
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case amount
        case customerId   = "customer_id"
        case recipientName  = "recipient_name"
        case recipientEmail = "recipient_email"
        case expiresAt    = "expires_at"
        case notes
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(GiftCard.centsToDollars(amountCents), forKey: .amount)
        try c.encodeIfPresent(customerId, forKey: .customerId)
        try c.encodeIfPresent(recipientName, forKey: .recipientName)
        try c.encodeIfPresent(recipientEmail, forKey: .recipientEmail)
        try c.encodeIfPresent(expiresAt, forKey: .expiresAt)
        try c.encodeIfPresent(notes, forKey: .notes)
    }
}

/// Server response for `POST /api/v1/gift-cards` (issue path).
/// The server returns `{ id, code }` — just enough to surface the code once.
public struct IssueGiftCardResponse: Decodable, Sendable, Equatable {
    public let id: Int64
    /// Plaintext code, returned exactly once — the only time it leaves the server.
    public let code: String

    public init(id: Int64, code: String) {
        self.id = id
        self.code = code
    }
}

// MARK: - List gift cards

/// A single row from `GET /api/v1/gift-cards`.
public struct GiftCardRow: Decodable, Sendable, Identifiable, Equatable {
    public let id: Int64
    public let code: String
    public let balanceCents: Int
    public let initialBalanceCents: Int
    public let status: String
    public let recipientName: String?
    public let recipientEmail: String?
    public let expiresAt: String?
    public let notes: String?
    public let createdAt: String

    public init(
        id: Int64,
        code: String,
        balanceCents: Int,
        initialBalanceCents: Int,
        status: String,
        recipientName: String? = nil,
        recipientEmail: String? = nil,
        expiresAt: String? = nil,
        notes: String? = nil,
        createdAt: String
    ) {
        self.id = id
        self.code = code
        self.balanceCents = balanceCents
        self.initialBalanceCents = initialBalanceCents
        self.status = status
        self.recipientName = recipientName
        self.recipientEmail = recipientEmail
        self.expiresAt = expiresAt
        self.notes = notes
        self.createdAt = createdAt
    }

    public var isActive: Bool { status.lowercased() == "active" }

    enum CodingKeys: String, CodingKey {
        case id, code, status, notes
        case currentBalance  = "current_balance"
        case initialBalance  = "initial_balance"
        case recipientName   = "recipient_name"
        case recipientEmail  = "recipient_email"
        case expiresAt       = "expires_at"
        case createdAt       = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        code = try c.decode(String.self, forKey: .code)
        let currentDollars = try c.decodeIfPresent(Decimal.self, forKey: .currentBalance) ?? 0
        let initialDollars = try c.decodeIfPresent(Decimal.self, forKey: .initialBalance) ?? 0
        balanceCents = GiftCard.dollarsToCents(currentDollars)
        initialBalanceCents = GiftCard.dollarsToCents(initialDollars)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "active"
        recipientName  = try c.decodeIfPresent(String.self, forKey: .recipientName)
        recipientEmail = try c.decodeIfPresent(String.self, forKey: .recipientEmail)
        expiresAt  = try c.decodeIfPresent(String.self, forKey: .expiresAt)
        notes      = try c.decodeIfPresent(String.self, forKey: .notes)
        createdAt  = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }
}

/// Pagination envelope from `GET /api/v1/gift-cards`.
public struct GiftCardListResponse: Decodable, Sendable {
    public let cards: [GiftCardRow]
    public let pagination: GiftCardPagination

    public init(cards: [GiftCardRow], pagination: GiftCardPagination) {
        self.cards = cards
        self.pagination = pagination
    }
}

public struct GiftCardPagination: Decodable, Sendable, Equatable {
    public let page: Int
    public let perPage: Int
    public let total: Int
    public let totalPages: Int

    public init(page: Int, perPage: Int, total: Int, totalPages: Int) {
        self.page = page
        self.perPage = perPage
        self.total = total
        self.totalPages = totalPages
    }

    enum CodingKeys: String, CodingKey {
        case page
        case perPage     = "per_page"
        case total
        case totalPages  = "total_pages"
    }
}

// MARK: - Store credit history

/// A single store-credit transaction row from
/// `GET /api/v1/refunds/credits/:customerId`.
public struct StoreCreditTransaction: Decodable, Sendable, Identifiable, Equatable {
    public let id: Int64
    public let amountCents: Int
    public let type: String
    public let notes: String?
    public let createdAt: String

    public init(id: Int64, amountCents: Int, type: String, notes: String? = nil, createdAt: String) {
        self.id = id
        self.amountCents = amountCents
        self.type = type
        self.notes = notes
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, type, notes
        case amount     = "amount"
        case createdAt  = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        let dollars = try c.decodeIfPresent(Decimal.self, forKey: .amount) ?? 0
        amountCents = GiftCard.dollarsToCents(abs(dollars))
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "credit"
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }
}

/// Full response from `GET /api/v1/refunds/credits/:customerId`.
public struct StoreCreditDetail: Decodable, Sendable {
    public let balanceCents: Int
    public let transactions: [StoreCreditTransaction]

    public init(balanceCents: Int, transactions: [StoreCreditTransaction]) {
        self.balanceCents = balanceCents
        self.transactions = transactions
    }

    enum CodingKeys: String, CodingKey {
        case balance
        case transactions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let dollars = try c.decodeIfPresent(Decimal.self, forKey: .balance) ?? 0
        balanceCents = GiftCard.dollarsToCents(dollars)
        transactions = try c.decodeIfPresent([StoreCreditTransaction].self, forKey: .transactions) ?? []
    }
}

// MARK: - APIClient extensions

public extension APIClient {

    // MARK: Issue

    /// `POST /api/v1/gift-cards` — issue a new gift card (admin/manager only).
    /// Returns `{ id, code }` — the plaintext code is returned exactly once.
    func issueGiftCard(_ request: IssueGiftCardRequest) async throws -> IssueGiftCardResponse {
        try await post("/api/v1/gift-cards", body: request, as: IssueGiftCardResponse.self)
    }

    // MARK: List

    /// `GET /api/v1/gift-cards` — paginated list with optional keyword + status filter.
    func listGiftCards(
        keyword: String? = nil,
        status: String? = nil,
        page: Int = 1,
        perPage: Int = 50
    ) async throws -> GiftCardListResponse {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
        ]
        if let keyword, !keyword.isEmpty {
            query.append(URLQueryItem(name: "keyword", value: keyword))
        }
        if let status, !status.isEmpty {
            query.append(URLQueryItem(name: "status", value: status))
        }
        return try await get("/api/v1/gift-cards", query: query, as: GiftCardListResponse.self)
    }

    // MARK: Store credit history

    /// `GET /api/v1/refunds/credits/:customerId` — balance + transaction history.
    func getStoreCreditDetail(customerId: Int64) async throws -> StoreCreditDetail {
        try await get("/api/v1/refunds/credits/\(customerId)", as: StoreCreditDetail.self)
    }
}
