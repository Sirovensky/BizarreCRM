import Foundation

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
}
