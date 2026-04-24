import Foundation

// MARK: - Marketing ancillary types (review solicitation + referrals)
//
// Campaign CRUD lives in CampaignsEndpoints.swift.
// Segment CRUD types live in the Marketing package (Models.swift) and are
// accessed via the Marketing-package extension in MarketingEndpoints.swift.
// This file adds the review and referral endpoint methods whose request/response
// shapes are small enough to live here without creating a circular dependency.

// MARK: - Review solicitation

/// Response from `GET reviews/last-request/:customerId`.
public struct MarketingReviewLastRequestResponse: Decodable, Sendable {
    /// ISO 8601 date of the last review request, or nil if never sent.
    public let lastRequestedAt: Date?

    public init(lastRequestedAt: Date?) {
        self.lastRequestedAt = lastRequestedAt
    }
}

/// Response from `POST reviews/request`.
public struct MarketingReviewRequestResponse: Decodable, Sendable {
    public let sent: Bool

    public init(sent: Bool) {
        self.sent = sent
    }
}

// MARK: - Referrals

/// Server row for a referral code.  `GET referrals/code/:customerId`
public struct MarketingReferralCodeRow: Decodable, Sendable {
    public let id: String
    public let customerId: String
    /// 8-char alphanumeric code.
    public let code: String
    public let uses: Int
    public let conversions: Int

    public init(id: String, customerId: String, code: String, uses: Int, conversions: Int) {
        self.id = id
        self.customerId = customerId
        self.code = code
        self.uses = uses
        self.conversions = conversions
    }
}

/// Entry in `GET referrals/leaderboard`.
public struct MarketingReferralLeaderEntry: Identifiable, Decodable, Sendable {
    public let id: String
    public let customerName: String
    public let referralCount: Int
    public let revenueGeneratedCents: Int

    public init(id: String, customerName: String, referralCount: Int, revenueGeneratedCents: Int) {
        self.id = id
        self.customerName = customerName
        self.referralCount = referralCount
        self.revenueGeneratedCents = revenueGeneratedCents
    }
}

public struct MarketingReferralLeaderboardResponse: Decodable, Sendable {
    public let entries: [MarketingReferralLeaderEntry]

    public init(entries: [MarketingReferralLeaderEntry]) {
        self.entries = entries
    }
}

// MARK: - APIClient extension

public extension APIClient {

    // MARK: Review solicitation

    /// `GET reviews/last-request/:customerId` — returns the date of the last
    /// review request sent to this customer (nil if never sent).
    func getReviewLastRequest(customerId: String) async throws -> MarketingReviewLastRequestResponse {
        try await get(
            "reviews/last-request/\(customerId)",
            as: MarketingReviewLastRequestResponse.self
        )
    }

    // MARK: Referrals

    /// `GET referrals/code/:customerId` — fetch or generate the referral code.
    func getReferralCode(customerId: String) async throws -> MarketingReferralCodeRow {
        try await get("referrals/code/\(customerId)", as: MarketingReferralCodeRow.self)
    }

    /// `GET referrals/leaderboard` — top referrers sorted by conversion count.
    func getReferralLeaderboard() async throws -> MarketingReferralLeaderboardResponse {
        try await get("referrals/leaderboard", as: MarketingReferralLeaderboardResponse.self)
    }
}
