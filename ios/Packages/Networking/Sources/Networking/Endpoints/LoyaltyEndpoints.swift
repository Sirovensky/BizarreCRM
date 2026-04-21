import Foundation

/// §38 — Loyalty balance + Apple Wallet pass wire formats.
///
/// Server routes targeted:
///   - `GET /api/v1/loyalty/balance/:customerId` — returns balance + tier.
///   - `GET /api/v1/loyalty/passes/:customerId`  — returns raw .pkpass bytes.
///
/// Neither endpoint is implemented server-side at the time of writing
/// (§38 loyalty scaffold). Both wrappers throw
/// `APITransportError.httpStatus(501, ...)` so callsites display a
/// "Coming soon" state instead of an unhandled error. Swap the stubs for
/// real calls when the server ships the endpoints.
///
/// Snake_case CodingKeys follow the project convention; the shared
/// `JSONDecoder` uses `.convertFromSnakeCase`, but explicit keys are
/// provided for clarity and to guard against field renames.

// MARK: - DTOs

/// Loyalty balance for a single customer.
public struct LoyaltyBalance: Decodable, Sendable {
    public let customerId: Int64
    public let points: Int
    /// Tier name: "bronze", "silver", "gold", "platinum" (lowercase,
    /// matches `LoyaltyTier.rawValue` in the Loyalty package).
    public let tier: String
    /// Lifetime spend in integer cents.
    public let lifetimeSpendCents: Int
    /// ISO-8601 membership start date.
    public let memberSince: String

    public init(
        customerId: Int64,
        points: Int,
        tier: String,
        lifetimeSpendCents: Int,
        memberSince: String
    ) {
        self.customerId = customerId
        self.points = points
        self.tier = tier
        self.lifetimeSpendCents = lifetimeSpendCents
        self.memberSince = memberSince
    }

    enum CodingKeys: String, CodingKey {
        case customerId        = "customer_id"
        case points
        case tier
        case lifetimeSpendCents = "lifetime_spend_cents"
        case memberSince       = "member_since"
    }
}

/// Pass metadata returned alongside or before the raw `.pkpass` download.
public struct LoyaltyPassInfo: Decodable, Sendable {
    public let customerId: Int64
    /// Direct URL to the signed `.pkpass` file, if the server hosts it.
    /// `nil` means the client should use the streaming endpoint instead.
    public let passUrl: String?
    /// Barcode payload embedded in the Wallet pass (e.g. a UUID string).
    public let barcode: String?

    public init(
        customerId: Int64,
        passUrl: String?,
        barcode: String?
    ) {
        self.customerId = customerId
        self.passUrl = passUrl
        self.barcode = barcode
    }

    enum CodingKeys: String, CodingKey {
        case customerId = "customer_id"
        case passUrl    = "pass_url"
        case barcode
    }
}

// MARK: - APIClient wrappers

public extension APIClient {
    /// Fetch the loyalty balance for `customerId`.
    ///
    /// Soft-absorbs 404 and 501 → throws
    /// `APITransportError.httpStatus(501, ...)` so the caller can show
    /// a "Coming soon" placeholder without crashing.
    func getLoyaltyBalance(customerId: Int64) async throws -> LoyaltyBalance {
        // Server endpoint not yet implemented — stub to 501.
        throw APITransportError.httpStatus(501, message: "Loyalty balance coming soon")
        // Uncomment when server ships:
        // return try await get("/api/v1/loyalty/balance/\(customerId)", as: LoyaltyBalance.self)
    }

    /// Download the raw `.pkpass` bytes for `customerId`.
    ///
    /// Uses `URLSession` directly because the response is binary, not a
    /// JSON envelope. Soft-absorbs 404 and 501 → throws
    /// `APITransportError.httpStatus(501, ...)`.
    func fetchLoyaltyPass(customerId: Int64) async throws -> Data {
        // Server endpoint not yet implemented — stub to 501.
        throw APITransportError.httpStatus(501, message: "Loyalty pass coming soon")
        // Uncomment when server ships and supply auth + base URL:
        // guard let base = await currentBaseURL() else {
        //     throw APITransportError.noBaseURL
        // }
        // let url = base.appendingPathComponent("/api/v1/loyalty/passes/\(customerId)")
        // var req = URLRequest(url: url)
        // req.httpMethod = "GET"
        // // Inject auth token when available (mirror APIClientImpl.request(_:)).
        // let (data, resp) = try await URLSession.shared.data(for: req)
        // guard let http = resp as? HTTPURLResponse else {
        //     throw APITransportError.invalidResponse
        // }
        // if http.statusCode == 404 || http.statusCode == 501 {
        //     throw APITransportError.httpStatus(http.statusCode, message: "Loyalty pass coming soon")
        // }
        // guard (200..<300).contains(http.statusCode) else {
        //     throw APITransportError.httpStatus(http.statusCode, message: nil)
        // }
        // return data
    }
}
