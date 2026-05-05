import Foundation

/// §38 — Loyalty balance + Apple Wallet pass wire formats.
///
/// Server routes used:
///   - `GET /api/v1/customers/:customerId/analytics` — lifetime_value in dollars.
///   - `GET /api/v1/membership/customer/:customerId` — active subscription + tier.
///   - `GET /api/v1/crm/customers/:customerId/wallet-pass?format=pkpass` — signed pass.
///
/// The dedicated `GET /api/v1/loyalty/balance/:customerId` endpoint does NOT
/// exist on the server-side staff API (only on the portal). `getLoyaltyBalance`
/// assembles an approximate `LoyaltyBalance` from the analytics + membership
/// endpoints. Loyalty points (earn/spend ledger) are not yet exposed via the
/// staff API — that field is stubbed to 0 until server ticket lands.
///
/// MISSING ENDPOINT: POST /api/v1/membership/:id/points/redeem (§38.2)
/// — redemption at POS is not yet wired. Returns 501 until server ships it.
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

// MARK: - Supporting DTOs (private assembly helpers)

/// Customer analytics — used to derive lifetime_spend_cents for the loyalty card.
private struct CustomerAnalyticsDTO: Decodable, Sendable {
    let totalTickets: Int?
    let lifetimeValue: Double?      // dollars (floating-point from server)
    let firstVisit: String?

    enum CodingKeys: String, CodingKey {
        case totalTickets    = "total_tickets"
        case lifetimeValue   = "lifetime_value"
        case firstVisit      = "first_visit"
    }
}

// MARK: - APIClient wrappers

public extension APIClient {

    /// Fetch a synthesised loyalty balance for `customerId`.
    ///
    /// Assembly strategy:
    ///  1. `GET /customers/:id/analytics`           → lifetime_value + first_visit date.
    ///  2. `GET /membership/customer/:id`           → active tier name.
    ///
    /// Points are not yet exposed via the staff API (only the portal has the
    /// loyalty_points ledger). The `points` field is stubbed to 0 until the
    /// server ships `GET /api/v1/customers/:id/loyalty-points`.
    ///
    /// Throws on 5xx network errors. 404 from analytics → `.httpStatus(404)`.
    func getLoyaltyBalance(customerId: Int64) async throws -> LoyaltyBalance {
        // Fetch analytics and subscription concurrently.
        async let analyticsTask = get(
            "/customers/\(customerId)/analytics",
            as: CustomerAnalyticsDTO.self
        )
        async let subscriptionTask: CustomerSubscriptionDTO? = {
            do {
                return try await get(
                    "/membership/customer/\(customerId)",
                    as: CustomerSubscriptionDTO?.self
                )
            } catch {
                return nil
            }
        }()

        let (analytics, subscription) = try await (analyticsTask, subscriptionTask)

        let lifetimeSpendCents = Int((analytics.lifetimeValue ?? 0.0) * 100.0)
        // Derive tier: prefer the active subscription tier name, fall back
        // to auto-computing from lifetime spend thresholds.
        let tierName: String
        if let subTierName = subscription?.tierName {
            tierName = subTierName.lowercased()
        } else {
            // Auto-tier from spend
            tierName = autoTierName(lifetimeSpendCents: lifetimeSpendCents)
        }

        // Member-since: first invoice visit, or subscription start, or today.
        let memberSince: String
        if let firstVisit = analytics.firstVisit {
            // Server returns "YYYY-MM-DD HH:MM:SS" — extract date part.
            memberSince = String(firstVisit.prefix(10))
        } else if let periodStart = subscription?.currentPeriodStart {
            memberSince = String(periodStart.prefix(10))
        } else {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            memberSince = df.string(from: Date())
        }

        return LoyaltyBalance(
            customerId: customerId,
            points: 0,          // TODO: wire when /customers/:id/loyalty-points ships
            tier: tierName,
            lifetimeSpendCents: lifetimeSpendCents,
            memberSince: memberSince
        )
    }

    /// Download the raw `.pkpass` bytes for `customerId`.
    ///
    /// Server route: `GET /crm/customers/:customerId/wallet-pass?format=pkpass`
    /// Requires `manager` or `admin` role.
    ///
    /// Throws `APITransportError.httpStatus(501, ...)` when pkpass signing is
    /// not yet configured on the tenant (server returns HTML fallback or 406).
    func fetchLoyaltyPass(customerId: Int64) async throws -> Data {
        guard let base = await currentBaseURL() else {
            throw APITransportError.noBaseURL
        }
        var comps = URLComponents(
            url: base.appendingPathComponent("/crm/customers/\(customerId)/wallet-pass"),
            resolvingAgainstBaseURL: false
        )
        comps?.queryItems = [URLQueryItem(name: "format", value: "pkpass")]
        guard let url = comps?.url else { throw APITransportError.invalidResponse }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/vnd.apple.pkpass", forHTTPHeaderField: "Accept")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APITransportError.invalidResponse }

        if http.statusCode == 404 || http.statusCode == 501 {
            throw APITransportError.httpStatus(http.statusCode, message: "Loyalty pass not configured")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APITransportError.httpStatus(http.statusCode, message: nil)
        }

        // Validate Content-Type — server may return HTML fallback if pkpass
        // signing is not configured. Treat that as "coming soon".
        let ct = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard ct.contains("pkpass") else {
            throw APITransportError.httpStatus(501, message: "Loyalty pass signing not configured")
        }

        return data
    }
}

// MARK: - Private helpers

private func autoTierName(lifetimeSpendCents: Int) -> String {
    // Mirror LoyaltyTier.minLifetimeSpendCents thresholds.
    switch lifetimeSpendCents {
    case ..<50_000:  return "bronze"
    case ..<100_000: return "silver"
    case ..<500_000: return "gold"
    default:         return "platinum"
    }
}
