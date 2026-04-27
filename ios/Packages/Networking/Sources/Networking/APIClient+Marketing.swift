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

// MARK: - CSAT / NPS survey DTOs

/// Envelope for `POST surveys/csat` — submits a 5-star CSAT rating.
public struct MarketingCSATSubmitRequest: Encodable, Sendable {
    public let customerId: String
    public let ticketId: String
    public let score: Int
    public let comment: String

    public init(customerId: String, ticketId: String, score: Int, comment: String) {
        self.customerId = customerId
        self.ticketId = ticketId
        self.score = score
        self.comment = comment
    }
}

/// Envelope for `POST surveys/nps` — submits a 0-10 NPS score.
public struct MarketingNPSSubmitRequest: Encodable, Sendable {
    public let customerId: String
    public let score: Int
    public let themes: [String]
    public let comment: String

    public init(customerId: String, score: Int, themes: [String], comment: String) {
        self.customerId = customerId
        self.score = score
        self.themes = themes
        self.comment = comment
    }
}

/// Shared success envelope returned by survey submit endpoints.
public struct MarketingSurveySubmitResponse: Decodable, Sendable {
    public let received: Bool

    public init(received: Bool) {
        self.received = received
    }
}

// MARK: - Review platform settings DTOs

/// Request / response body for `POST/GET settings/review-platforms`.
public struct MarketingReviewPlatformSettings: Codable, Sendable {
    public var googleBusinessURL: URL?
    public var yelpURL: URL?
    public var facebookURL: URL?

    public init(googleBusinessURL: URL? = nil, yelpURL: URL? = nil, facebookURL: URL? = nil) {
        self.googleBusinessURL = googleBusinessURL
        self.yelpURL = yelpURL
        self.facebookURL = facebookURL
    }
}

/// Request body for `POST reviews/request`.
public struct MarketingReviewRequestBody: Encodable, Sendable {
    public let customerId: String
    public let platform: String?
    public let template: String

    public init(customerId: String, platform: String?, template: String) {
        self.customerId = customerId
        self.platform = platform
        self.template = template
    }
}

// MARK: - Referral rule DTOs

/// Referral credit rule — flat credit or percentage of sale.
public struct MarketingReferralRule: Codable, Sendable {
    public enum RuleType: String, Codable, Sendable, CaseIterable {
        case flat, percentage
    }

    public let type: RuleType
    public let senderCreditCents: Int
    public let receiverCreditCents: Int
    public let minSaleCents: Int
    public let percentageBps: Int

    public init(
        type: RuleType,
        senderCreditCents: Int,
        receiverCreditCents: Int,
        minSaleCents: Int,
        percentageBps: Int
    ) {
        self.type = type
        self.senderCreditCents = senderCreditCents
        self.receiverCreditCents = receiverCreditCents
        self.minSaleCents = minSaleCents
        self.percentageBps = percentageBps
    }
}

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

    /// `POST reviews/request` — send a review request to the customer.
    @discardableResult
    func sendReviewRequest(body: MarketingReviewRequestBody) async throws -> MarketingReviewRequestResponse {
        try await post("reviews/request", body: body, as: MarketingReviewRequestResponse.self)
    }

    /// `POST settings/review-platforms` — save tenant review platform URLs.
    @discardableResult
    func saveReviewPlatformSettings(_ settings: MarketingReviewPlatformSettings) async throws -> MarketingReviewPlatformSettings {
        try await post("settings/review-platforms", body: settings, as: MarketingReviewPlatformSettings.self)
    }

    // MARK: Surveys

    /// `POST surveys/csat` — submit a 5-star CSAT rating.
    @discardableResult
    func submitCSAT(_ body: MarketingCSATSubmitRequest) async throws -> MarketingSurveySubmitResponse {
        try await post("surveys/csat", body: body, as: MarketingSurveySubmitResponse.self)
    }

    /// `POST surveys/nps` — submit a 0-10 NPS score.
    @discardableResult
    func submitNPS(_ body: MarketingNPSSubmitRequest) async throws -> MarketingSurveySubmitResponse {
        try await post("surveys/nps", body: body, as: MarketingSurveySubmitResponse.self)
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

    /// `POST referrals/rule` — save the global referral credit rule.
    @discardableResult
    func saveReferralRule(_ rule: MarketingReferralRule) async throws -> MarketingReferralRule {
        try await post("referrals/rule", body: rule, as: MarketingReferralRule.self)
    }
}
