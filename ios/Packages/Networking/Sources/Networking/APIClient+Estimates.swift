import Foundation

// MARK: - §8 Estimates — list-status filter

/// Maps the §8.1 status tab selection to the server's `status` query param.
public enum EstimateStatusFilter: String, CaseIterable, Sendable {
    case all
    case draft
    case sent
    case approved
    case rejected
    case expired
    case converted

    public var displayName: String {
        switch self {
        case .all:       return "All"
        case .draft:     return "Draft"
        case .sent:      return "Sent"
        case .approved:  return "Approved"
        case .rejected:  return "Rejected"
        case .expired:   return "Expired"
        case .converted: return "Converted"
        }
    }

    /// `nil` means no status filter (fetch all).
    public var queryValue: String? {
        self == .all ? nil : rawValue
    }
}

// MARK: - §8 cursor pagination

/// Thin wrapper that adds cursor pagination to the list response.
public struct EstimatesCursorResponse: Decodable, Sendable {
    public let estimates: [Estimate]
    public let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case estimates
        case nextCursor = "next_cursor"
    }
}

// MARK: - §8.2 send request/response

/// `POST /api/v1/estimates/:id/send`
public struct EstimateSendRequest: Encodable, Sendable {
    /// If `true`, the server triggers the SMS notification.
    public let sendSms: Bool?
    /// If `true`, the server triggers the email notification.
    public let sendEmail: Bool?

    public init(sendSms: Bool? = nil, sendEmail: Bool? = nil) {
        self.sendSms = sendSms
        self.sendEmail = sendEmail
    }

    enum CodingKeys: String, CodingKey {
        case sendSms   = "send_sms"
        case sendEmail = "send_email"
    }
}

public struct EstimateSendResponse: Decodable, Sendable {
    public let estimateId: Int64
    public let approvalLink: String?

    enum CodingKeys: String, CodingKey {
        case estimateId   = "estimate_id"
        case approvalLink = "approval_link"
    }
}

// MARK: - §8.2 approve (staff-assisted)

/// `POST /api/v1/estimates/:id/approve`
/// Staff-assisted approval: send `token = nil` and `staffApproved = true`.
public struct EstimateApproveRequest: Encodable, Sendable {
    public let token: String?
    public let staffApproved: Bool?
    /// Base64-encoded PNG of the signature captured via PKCanvasView.
    public let signatureData: String?

    public init(token: String? = nil, staffApproved: Bool? = true, signatureData: String? = nil) {
        self.token = token
        self.staffApproved = staffApproved
        self.signatureData = signatureData
    }

    enum CodingKeys: String, CodingKey {
        case token
        case staffApproved = "staff_approved"
        case signatureData = "signature_data"
    }
}

public struct EstimateApproveResponse: Decodable, Sendable {
    public let estimateId: Int64
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case estimateId = "estimate_id"
        case status
    }
}

// MARK: - §8.2 reject

/// `PUT /api/v1/estimates/:id` with `{ status: "rejected", rejection_reason: "..." }`
public struct EstimateRejectRequest: Encodable, Sendable {
    public let status: String = "rejected"
    public let rejectionReason: String

    public init(reason: String) {
        self.rejectionReason = reason
    }

    enum CodingKeys: String, CodingKey {
        case status
        case rejectionReason = "rejection_reason"
    }
}

// MARK: - §8.2 convert-to-invoice

/// `POST /api/v1/estimates/:id/convert-to-invoice` (if endpoint exists; else via §74 shim note).
public struct ConvertEstimateToInvoiceResponse: Decodable, Sendable {
    public let invoiceId: Int64?

    enum CodingKeys: String, CodingKey {
        case invoiceId = "invoice_id"
    }
}

// MARK: - §8.2 versions

public struct EstimateVersion: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let estimateId: Int64
    public let versionNumber: Int
    public let createdAt: String?
    public let total: Double?
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case id
        case estimateId   = "estimate_id"
        case versionNumber = "version_number"
        case createdAt     = "created_at"
        case total, status
    }
}

public struct EstimateVersionsResponse: Decodable, Sendable {
    public let versions: [EstimateVersion]
}

// MARK: - §8 bulk actions

public enum EstimateBulkAction: String, Sendable {
    case send
    case delete
    case export
}

public struct EstimateBulkRequest: Encodable, Sendable {
    public let estimateIds: [Int64]
    public let action: String

    public init(ids: [Int64], action: EstimateBulkAction) {
        self.estimateIds = ids
        self.action = action.rawValue
    }

    enum CodingKeys: String, CodingKey {
        case estimateIds = "estimate_ids"
        case action
    }
}

// MARK: - §8.4 Expire body

/// Body for `PUT /api/v1/estimates/:id` — manually expire.
struct EstimateExpireBody: Encodable, Sendable {
    let status: String = "expired"
}

// MARK: - §8.3 Idempotency-key wrapper

/// Wraps `CreateEstimateRequest` to append `idempotency_key` to the JSON body.
/// The server can use this to deduplicate retries.
struct CreateEstimateRequestWithKey: Encodable, Sendable {
    let base: CreateEstimateRequest
    let idempotencyKey: String

    // Forward all base fields + add idempotency_key.
    func encode(to encoder: Encoder) throws {
        try base.encode(to: encoder)
        var container = encoder.container(keyedBy: ExtraKey.self)
        try container.encode(idempotencyKey, forKey: .idempotencyKey)
    }

    private enum ExtraKey: String, CodingKey {
        case idempotencyKey = "idempotency_key"
    }
}

// MARK: - Estimates — sign-URL issuance (append-only)
//
// Confirmed server routes (estimateSign.routes.ts — authedRouter):
//   POST /api/v1/estimates/:id/sign-url
//     Body: { ttl_minutes?: Int }
//     Response envelope → { success, data: { url, expires_at, estimate_id } }
//
// Public sign-capture routes (publicRouter) are customer-facing web flows —
// they do NOT require auth and are NOT called from the iOS staff app.
// The iOS app only issues sign-URL tokens so staff can share the link with customers.

// MARK: - IssueSignUrlRequest

/// Body for `POST /api/v1/estimates/:id/sign-url`.
/// `ttlMinutes` is optional; server defaults to 4 320 min (3 days).
public struct IssueSignUrlRequest: Encodable, Sendable {
    public let ttlMinutes: Int?

    public init(ttlMinutes: Int? = nil) {
        self.ttlMinutes = ttlMinutes
    }

    enum CodingKeys: String, CodingKey {
        case ttlMinutes = "ttl_minutes"
    }
}

// MARK: - IssueSignUrlResponse

/// Decoded from `data` in the sign-url response envelope.
public struct IssueSignUrlResponse: Decodable, Sendable {
    /// The full public URL the customer opens to sign.
    public let url: String
    /// ISO-8601 / SQLite timestamp when the token expires.
    public let expiresAt: String
    /// The estimate this token belongs to.
    public let estimateId: Int64

    public init(url: String, expiresAt: String, estimateId: Int64) {
        self.url = url
        self.expiresAt = expiresAt
        self.estimateId = estimateId
    }

    enum CodingKeys: String, CodingKey {
        case url
        case expiresAt  = "expires_at"
        case estimateId = "estimate_id"
    }
}

// MARK: - EstimatesCursorPage
//
// §8.1: Cursor-based pagination response.
// Server returns: { estimates: [...], next_cursor: String?, has_more: Bool }
// When `nextCursor` is nil the list is exhausted.

public struct EstimatesCursorPage: Decodable, Sendable {
    public let estimates: [Estimate]
    public let nextCursor: String?
    public let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case estimates
        case nextCursor = "next_cursor"
        case hasMore    = "has_more"
    }
}

// MARK: - CreateEstimateWithIdempotencyRequest
//
// §8.3: Wraps CreateEstimateRequest, adding an `idempotency_key` field.
// The server uses this UUID to deduplicate duplicate POSTs (e.g. on retry after
// a timeout). Sent as a JSON body field (not a header) per established pattern.

public struct CreateEstimateWithIdempotencyRequest: Encodable, Sendable {
    public let customerId: Int64
    public let subject: String?
    public let notes: String?
    public let validUntil: String?
    public let discount: Double?
    public let lineItems: [EstimateLineItemRequest]?
    /// Client-generated UUID preventing duplicate creates on retry.
    public let idempotencyKey: String

    public init(
        customerId: Int64,
        subject: String? = nil,
        notes: String? = nil,
        validUntil: String? = nil,
        discount: Double? = nil,
        lineItems: [EstimateLineItemRequest]? = nil,
        idempotencyKey: String
    ) {
        self.customerId = customerId
        self.subject = subject
        self.notes = notes
        self.validUntil = validUntil
        self.discount = discount
        self.lineItems = lineItems
        self.idempotencyKey = idempotencyKey
    }

    enum CodingKeys: String, CodingKey {
        case subject, notes, discount
        case customerId     = "customer_id"
        case validUntil     = "valid_until"
        case lineItems      = "line_items"
        case idempotencyKey = "idempotency_key"
    }
}

// MARK: - APIClient extension

public extension APIClient {
    /// `POST /api/v1/estimates/:id/sign-url`
    ///
    /// Issues a single-use HMAC-signed customer e-sign URL.
    /// Requires `estimates.edit` permission + admin/manager role (enforced server-side).
    /// Rate-limited to 5 issuances per estimate per hour.
    func issueEstimateSignUrl(
        estimateId: Int64,
        ttlMinutes: Int? = nil
    ) async throws -> IssueSignUrlResponse {
        let body = IssueSignUrlRequest(ttlMinutes: ttlMinutes)
        return try await post(
            "/api/v1/estimates/\(estimateId)/sign-url",
            body: body,
            as: IssueSignUrlResponse.self
        )
    }

    // MARK: - §8.1 Cursor-based pagination

    /// `GET /api/v1/estimates?cursor=<opaque>&limit=<n>&keyword=<q>&status=<s>`
    ///
    /// Fetches one page of estimates using opaque cursor pagination.
    /// Pass `cursor: nil` to fetch the first page.
    /// The response includes `next_cursor` (nil when exhausted) + `has_more`.
    func listEstimatesCursor(
        cursor: String? = nil,
        limit: Int = 50,
        keyword: String? = nil,
        status: String? = nil
    ) async throws -> EstimatesCursorPage {
        var query: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let c = cursor { query.append(URLQueryItem(name: "cursor", value: c)) }
        if let k = keyword, !k.isEmpty { query.append(URLQueryItem(name: "keyword", value: k)) }
        if let s = status { query.append(URLQueryItem(name: "status", value: s)) }
        // Fallback: server may not yet support cursor pagination — if response
        // decoding fails (missing next_cursor/has_more), catch and wrap the
        // old envelope. The do/catch is handled by the caller via CachedRepository.
        return try await get("/api/v1/estimates", query: query, as: EstimatesCursorPage.self)
    }

    // MARK: - §8.3 Idempotent create

    /// `POST /api/v1/estimates` with an idempotency key to deduplicate retries.
    ///
    /// The `idempotencyKey` is a client-generated UUID included in the request body.
    /// The server indexes on this key and returns the previously-created estimate if
    /// the same key is submitted twice within the dedup window.
    func createEstimateIdempotent(_ req: CreateEstimateWithIdempotencyRequest) async throws -> CreatedResource {
        try await post("/api/v1/estimates", body: req, as: CreatedResource.self)
    }
}
