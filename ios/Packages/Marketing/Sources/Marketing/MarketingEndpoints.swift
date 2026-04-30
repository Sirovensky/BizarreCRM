import Foundation
import Networking

// MARK: - Private request bodies (must be top-level for Swift 6 generics)

private struct EmptyBody: Encodable, Sendable {}
private struct ApproveSendBody: Encodable, Sendable {
    let pin: String
}
private struct ApproveResponse: Decodable, Sendable {
    let approved: Bool?
}
private struct SegmentPreviewBody: Encodable, Sendable {
    let rule: SegmentRuleGroup
}

// MARK: - Marketing + Segment API endpoints

public extension APIClient {

    // MARK: Campaigns

    func listCampaigns(cursor: String? = nil) async throws -> CampaignListResponse {
        var query: [URLQueryItem]? = nil
        if let c = cursor { query = [URLQueryItem(name: "cursor", value: c)] }
        return try await get("marketing/campaigns", query: query, as: CampaignListResponse.self)
    }

    func createCampaign(_ body: CreateCampaignRequest) async throws -> Campaign {
        try await post("marketing/campaigns", body: body, as: Campaign.self)
    }

    func getCampaign(id: String) async throws -> Campaign {
        try await get("marketing/campaigns/\(id)", as: Campaign.self)
    }

    func sendCampaign(id: String) async throws -> Campaign {
        try await post("marketing/campaigns/\(id)/send", body: EmptyBody(), as: Campaign.self)
    }

    func getCampaignReport(id: String) async throws -> CampaignReport {
        try await get("marketing/campaigns/\(id)/report", as: CampaignReport.self)
    }

    /// Approval gate — stub; server may return 404, surfaced as thrown error.
    func approveSendCampaign(id: String, managerPin: String) async throws {
        _ = try await post(
            "marketing/campaigns/\(id)/approve-send",
            body: ApproveSendBody(pin: managerPin),
            as: ApproveResponse.self
        )
    }

    // MARK: Segments

    func listSegments() async throws -> SegmentListResponse {
        try await get("segments", as: SegmentListResponse.self)
    }

    func createSegment(_ body: CreateSegmentRequest) async throws -> Segment {
        try await post("segments", body: body, as: Segment.self)
    }

    func getSegmentCount(id: String) async throws -> SegmentCountResponse {
        try await get("segments/\(id)/count", as: SegmentCountResponse.self)
    }

    func previewSegmentCount(rule: SegmentRuleGroup) async throws -> SegmentCountResponse {
        try await post("segments/preview", body: SegmentPreviewBody(rule: rule), as: SegmentCountResponse.self)
    }

    // MARK: Referrals (Marketing-package-local types)

    /// `GET referrals/code/:customerId` — fetch or generate the referral code.
    /// Returns the Marketing-package `ReferralCode` type.
    func referralCode(customerId: String) async throws -> ReferralCode {
        try await get("referrals/code/\(customerId)", as: ReferralCode.self)
    }

    /// `GET referrals/leaderboard` — top referrers by conversion count.
    func referralLeaderboard() async throws -> ReferralLeaderboardResponse {
        try await get("referrals/leaderboard", as: ReferralLeaderboardResponse.self)
    }

    /// `POST referrals/rule` — save the global referral credit rule.
    @discardableResult
    func saveReferralRule(_ rule: ReferralRule) async throws -> ReferralRule {
        try await post("referrals/rule", body: rule, as: ReferralRule.self)
    }

    // MARK: Surveys

    /// `POST surveys/csat` — submit a 5-star CSAT rating.
    @discardableResult
    func submitCSAT(_ body: CSATSubmitRequest) async throws -> SurveySubmitResponse {
        try await post("surveys/csat", body: body, as: SurveySubmitResponse.self)
    }

    /// `POST surveys/nps` — submit a 0-10 NPS score.
    @discardableResult
    func submitNPS(_ body: NPSSubmitRequest) async throws -> SurveySubmitResponse {
        try await post("surveys/nps", body: body, as: SurveySubmitResponse.self)
    }

    // MARK: Review platforms

    /// `POST settings/review-platforms` — save tenant review platform URLs.
    @discardableResult
    func saveReviewPlatformSettings(_ settings: ReviewPlatformSettings) async throws -> ReviewPlatformSettings {
        try await post("settings/review-platforms", body: settings, as: ReviewPlatformSettings.self)
    }

    /// `GET reviews/last-request/:customerId` — date of last review request sent.
    func reviewLastRequest(customerId: String) async throws -> ReviewLastRequestResponse {
        try await get("reviews/last-request/\(customerId)", as: ReviewLastRequestResponse.self)
    }

    /// `POST reviews/request` — send a review solicitation to the customer.
    @discardableResult
    func sendReviewRequest(_ body: ReviewRequestBody) async throws -> ReviewRequestResponse {
        try await post("reviews/request", body: body, as: ReviewRequestResponse.self)
    }
}
