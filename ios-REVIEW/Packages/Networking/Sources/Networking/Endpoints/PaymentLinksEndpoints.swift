import Foundation

/// §41 — payment links DTOs + APIClient wrappers.
///
/// Server routes live in `packages/server/src/routes/paymentLinks.routes.ts`:
///   • `POST /api/v1/payment-links` (manager/admin) — body accepts DOLLARS
///     (the server multiplies by 100 internally). Response envelope:
///         `{ success: true, data: { id, token } }`.
///     Note: the server does **not** return the full URL — iOS reconstructs
///     it via `APIClient.currentBaseURL() + /pay/<token>` per §74 of
///     `ios/docs/api-gap-audit.md`.
///   • `GET /api/v1/payment-links/:id` — returns the full row including
///     `status` ("active" / "paid" / "expired" / "cancelled"), `paid_at`,
///     `expires_at`, `amount_cents`. No dedicated `/status` endpoint — the
///     polling fallback re-reads this row every 10 s.
///
/// Money on the wire: the DB stores `amount_cents` (integer) but the create
/// POST takes dollars (double) because the legacy admin UI sends it that
/// way. The iOS API surface is cents-only; the encoder converts at the edge.

// MARK: - Create

/// iOS-side request shape. `amountCents` is the canonical form; the
/// encoder converts to dollars before POSTing. Optional fields mirror the
/// server: any non-nil invoice / customer id is FK-checked server-side.
public struct CreatePaymentLinkRequest: Encodable, Sendable, Equatable {
    public let amountCents: Int
    public let customerId: Int64?
    public let description: String?
    public let expiresAt: String?
    public let invoiceId: Int64?

    public init(
        amountCents: Int,
        customerId: Int64? = nil,
        description: String? = nil,
        expiresAt: String? = nil,
        invoiceId: Int64? = nil
    ) {
        self.amountCents = amountCents
        self.customerId = customerId
        self.description = description
        self.expiresAt = expiresAt
        self.invoiceId = invoiceId
    }

    enum CodingKeys: String, CodingKey {
        case amount
        case customerId   = "customer_id"
        case description
        case expiresAt    = "expires_at"
        case invoiceId    = "invoice_id"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Server accepts dollars (Double). Convert from cents so callers
        // never have to think about the unit mismatch.
        let dollars = Double(amountCents) / 100.0
        try container.encode(dollars, forKey: .amount)
        try container.encodeIfPresent(customerId, forKey: .customerId)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
        try container.encodeIfPresent(invoiceId, forKey: .invoiceId)
    }
}

/// Response from create — only id + token. The full row is served via
/// `GET /payment-links/:id` (decoded as `PaymentLink`).
public struct CreatePaymentLinkResponse: Decodable, Sendable {
    public let id: Int64
    public let token: String
}

// MARK: - Read

/// Full payment-link row. Decoded from both the create → getPaymentLink
/// flow and the list view. Snake-case keys map to the DB columns.
public struct PaymentLink: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    /// Server calls it `token`; short-id for URL building.
    public let shortId: String?
    /// Reconstructed share URL. The server does not populate this — the
    /// wrapper fills it in from `APIClient.currentBaseURL()`.
    public let url: String
    public let status: String
    public let amountCents: Int
    public let createdAt: String?
    public let expiresAt: String?
    public let paidAt: String?
    public let description: String?
    public let customerId: Int64?
    public let invoiceId: Int64?

    public init(
        id: Int64,
        shortId: String?,
        url: String,
        status: String,
        amountCents: Int,
        createdAt: String?,
        expiresAt: String?,
        paidAt: String?,
        description: String? = nil,
        customerId: Int64? = nil,
        invoiceId: Int64? = nil
    ) {
        self.id = id
        self.shortId = shortId
        self.url = url
        self.status = status
        self.amountCents = amountCents
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.paidAt = paidAt
        self.description = description
        self.customerId = customerId
        self.invoiceId = invoiceId
    }

    /// Enum view of the status string for exhaustive UI switching.
    public enum Status: String, Sendable {
        case active
        case paid
        case expired
        case cancelled
        case unknown
    }

    public var statusKind: Status { Status(rawValue: status.lowercased()) ?? .unknown }
    public var isPaid: Bool { statusKind == .paid }
    public var isActive: Bool { statusKind == .active }

    enum CodingKeys: String, CodingKey {
        case id, status, description, token, url
        case amountCents  = "amount_cents"
        case createdAt    = "created_at"
        case expiresAt    = "expires_at"
        case paidAt       = "paid_at"
        case customerId   = "customer_id"
        case invoiceId    = "invoice_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int64.self, forKey: .id)
        // `shortId` comes across the wire as `token`.
        self.shortId = try c.decodeIfPresent(String.self, forKey: .token)
        // Server doesn't return a full URL — if one is present (e.g. a
        // synthetic test fixture) prefer it, otherwise leave empty and let
        // the wrapper backfill from `currentBaseURL + /pay/<token>`.
        self.url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        self.status = try c.decode(String.self, forKey: .status)
        self.amountCents = try c.decode(Int.self, forKey: .amountCents)
        self.createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        self.expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt)
        self.paidAt = try c.decodeIfPresent(String.self, forKey: .paidAt)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.customerId = try c.decodeIfPresent(Int64.self, forKey: .customerId)
        self.invoiceId = try c.decodeIfPresent(Int64.self, forKey: .invoiceId)
    }

    /// Copy with a rebuilt share URL. Used by the wrapper to inject the
    /// reconstructed `/pay/<token>` URL after decoding.
    public func withURL(_ url: String) -> PaymentLink {
        PaymentLink(
            id: id,
            shortId: shortId,
            url: url,
            status: status,
            amountCents: amountCents,
            createdAt: createdAt,
            expiresAt: expiresAt,
            paidAt: paidAt,
            description: description,
            customerId: customerId,
            invoiceId: invoiceId
        )
    }
}

// MARK: - URL builder

/// Build the customer-facing pay URL from a token + the active base URL.
/// Exposed so tests can exercise the shape without a live `APIClient`.
public func makePaymentLinkURL(baseURL: URL?, token: String) -> String {
    guard !token.isEmpty else { return "" }
    guard let baseURL else { return "/pay/\(token)" }
    // `baseURL` typically points at `.../api/v1` — strip that back to the
    // origin so the share URL targets the public /pay page, not an API route.
    var scheme = baseURL.scheme ?? "https"
    if scheme != "https" && scheme != "http" { scheme = "https" }
    let host = baseURL.host ?? ""
    let port = baseURL.port.map { ":\($0)" } ?? ""
    return "\(scheme)://\(host)\(port)/pay/\(token)"
}

// MARK: - APIClient wrappers

public extension APIClient {
    /// Create a payment link. Returns the full `PaymentLink` with the
    /// share URL pre-populated. The server only emits `{id, token}` so we
    /// do a follow-up `GET` to fetch the canonical row, then rewrite
    /// `url` using the current base URL.
    func createPaymentLink(_ request: CreatePaymentLinkRequest) async throws -> PaymentLink {
        let created = try await post(
            "/api/v1/payment-links",
            body: request,
            as: CreatePaymentLinkResponse.self
        )
        return try await getPaymentLink(id: created.id, fallbackToken: created.token)
    }

    /// Read a payment link by id — used by the create flow + polling loop.
    /// `fallbackToken` covers the race where the server returns a token
    /// on create but the follow-up GET somehow lacks it (never observed,
    /// belt-and-braces).
    func getPaymentLink(id: Int64, fallbackToken: String? = nil) async throws -> PaymentLink {
        let link = try await get(
            "/api/v1/payment-links/\(id)",
            as: PaymentLink.self
        )
        let token = link.shortId?.isEmpty == false ? link.shortId! : (fallbackToken ?? "")
        let base = await currentBaseURL()
        let url = makePaymentLinkURL(baseURL: base, token: token)
        // Re-hydrate with reconstructed token + url so call sites never
        // see an empty URL.
        let withToken: PaymentLink = link.shortId?.isEmpty == false
            ? link
            : PaymentLink(
                id: link.id,
                shortId: token.isEmpty ? nil : token,
                url: link.url,
                status: link.status,
                amountCents: link.amountCents,
                createdAt: link.createdAt,
                expiresAt: link.expiresAt,
                paidAt: link.paidAt,
                description: link.description,
                customerId: link.customerId,
                invoiceId: link.invoiceId
            )
        return withToken.withURL(url)
    }

    /// List recent payment links (newest first, up to 500 per server cap).
    /// Optional status filter is passed as a query item when present.
    func listPaymentLinks(status: String? = nil) async throws -> [PaymentLink] {
        var query: [URLQueryItem] = []
        if let status, !status.isEmpty {
            query.append(URLQueryItem(name: "status", value: status))
        }
        let rows = try await get(
            "/api/v1/payment-links",
            query: query.isEmpty ? nil : query,
            as: [PaymentLink].self
        )
        let base = await currentBaseURL()
        return rows.map { row in
            let token = row.shortId ?? ""
            return row.withURL(makePaymentLinkURL(baseURL: base, token: token))
        }
    }

    /// Cancel an active payment link. Server returns `{id, status}`; we
    /// ignore the payload and re-fetch if the caller cares.
    func cancelPaymentLink(id: Int64) async throws {
        try await delete("/api/v1/payment-links/\(id)")
    }
}
