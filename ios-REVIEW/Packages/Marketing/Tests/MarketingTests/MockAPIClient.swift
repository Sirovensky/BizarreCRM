import Foundation
import Networking
@testable import Marketing

// Top-level types for mock use (Swift 6: no nested types in generic functions)
private struct MockApproveResponse: Decodable, Sendable { let approved: Bool? }

// MARK: - Shared fixture builders

func makeCampaignServerRow(
    id: Int = 1, name: String = "Test", status: String = "draft",
    type: String = "custom", channel: String = "sms",
    sentCount: Int = 0, repliedCount: Int = 0, convertedCount: Int = 0
) -> CampaignServerRow {
    CampaignServerRow(
        id: id, name: name, type: type, segmentId: nil,
        channel: channel, templateSubject: nil, templateBody: "Hello",
        triggerRuleJson: nil, status: status,
        sentCount: sentCount, repliedCount: repliedCount, convertedCount: convertedCount,
        createdAt: "2024-01-01T00:00:00Z", lastRunAt: nil
    )
}

/// Minimal mock APIClient for unit tests. Sendable-safe via actors.
actor MockAPIClient: APIClient {
    // MARK: - Campaign stubs (legacy list/create/send path)
    var campaignListResult: Result<CampaignListResponse, Error> = .success(CampaignListResponse(campaigns: [], nextCursor: nil))
    var campaignCreateResult: Result<Campaign, Error> = .success(Campaign(id: "1", name: "Test", status: .draft, template: "Hello", createdAt: Date()))
    var campaignGetResult: Result<Campaign, Error> = .success(Campaign(id: "1", name: "Test", status: .draft, template: "Hello", createdAt: Date()))
    var campaignSendResult: Result<Campaign, Error> = .success(Campaign(id: "1", name: "Test", status: .sending, template: "Hello", createdAt: Date()))
    var campaignReportResult: Result<CampaignReport, Error> = .success(CampaignReport(delivered: 10, failed: 1, optedOut: 0, replies: 2))
    var approveSendResult: Result<Void, Error> = .success(())

    // MARK: - Server row campaign stubs
    var campaignServerListResult: Result<[CampaignServerRow], Error> = .success([])
    var campaignServerGetResult: Result<CampaignServerRow, Error> = .success(makeCampaignServerRow())
    var campaignServerCreateResult: Result<CampaignServerRow, Error> = .success(makeCampaignServerRow())
    var campaignServerPatchResult: Result<CampaignServerRow, Error> = .success(makeCampaignServerRow())
    var campaignAudiencePreviewResult: Result<CampaignAudiencePreview, Error> = .success(
        CampaignAudiencePreview(campaignId: 1, totalRecipients: 42, preview: [])
    )
    var campaignStatsResult: Result<CampaignStats, Error> = .success(
        CampaignStats(
            campaign: makeCampaignServerRow(sentCount: 10, repliedCount: 2, convertedCount: 1),
            counts: CampaignStatCounts(sent: 10, failed: 0, replied: 2, converted: 1)
        )
    )
    var campaignRunNowResult: Result<CampaignRunNowResult, Error> = .success(
        CampaignRunNowResult(attempted: 5, sent: 5, failed: 0, skipped: 0)
    )
    var smsGroupsResult: Result<[SmsGroup], Error> = .success([])

    // MARK: - Segment stubs
    var segmentListResult: Result<SegmentListResponse, Error> = .success(SegmentListResponse(segments: []))
    var segmentCreateResult: Result<Segment, Error> = .success(Segment(id: "s1", name: "Test", rule: SegmentRuleGroup(), cachedCount: 0))
    var segmentCountResult: Result<SegmentCountResponse, Error> = .success(SegmentCountResponse(count: 42))
    var previewCountResult: Result<SegmentCountResponse, Error> = .success(SegmentCountResponse(count: 17))

    // MARK: - Referral stubs
    var referralCodeResult: Result<ReferralCode, Error> = .success(
        ReferralCode(id: "rc1", customerId: "cust1", code: "ABC12345", createdAt: Date(), uses: 0, conversions: 0)
    )
    var referralRuleResult: Result<ReferralRule, Error> = .success(ReferralRule.default)

    // MARK: - Review stubs
    var reviewLastRequestResult: Result<ReviewLastRequestResponse, Error> = .success(ReviewLastRequestResponse(lastRequestedAt: nil))
    var reviewRequestResult: Result<ReviewRequestResponse, Error> = .success(ReviewRequestResponse(sent: true))

    // MARK: - Survey stubs
    var csatSubmitResult: Result<SurveySubmitResponse, Error> = .success(SurveySubmitResponse(received: true))
    var npsSubmitResult: Result<SurveySubmitResponse, Error> = .success(SurveySubmitResponse(received: true))

    // MARK: - Call tracking
    var createCampaignCalled = 0
    var sendCampaignCalled = 0
    var createSegmentCalled = 0
    var previewCountCalled = 0
    var approveSendCalled = 0
    var campaignServerCreateCalled = 0
    var campaignServerPatchCalled = 0
    var campaignServerDeleteCalled = 0
    var runNowCalled = 0
    var audiencePreviewCalled = 0
    var lastGetPath: String = ""
    var lastPostPath: String = ""
    var reviewRequestCalled = 0
    var csatSubmitCalled = 0
    var npsSubmitCalled = 0

    // MARK: - Setters (for tests that need to inject from outside)

    func setReferralCodeResult(_ result: Result<ReferralCode, Error>) {
        referralCodeResult = result
    }

    func setReviewLastRequestResult(_ result: Result<ReviewLastRequestResponse, Error>) {
        reviewLastRequestResult = result
    }

    func setReviewRequestResult(_ result: Result<ReviewRequestResponse, Error>) {
        reviewRequestResult = result
    }

    func setCsatResult(_ result: Result<SurveySubmitResponse, Error>) {
        csatSubmitResult = result
    }

    func setNpsResult(_ result: Result<SurveySubmitResponse, Error>) {
        npsSubmitResult = result
    }

    func setCampaignServerListResult(_ result: Result<[CampaignServerRow], Error>) {
        campaignServerListResult = result
    }

    func setCampaignStatsResult(_ result: Result<CampaignStats, Error>) {
        campaignStatsResult = result
    }

    func setAudiencePreviewResult(_ result: Result<CampaignAudiencePreview, Error>) {
        campaignAudiencePreviewResult = result
    }

    func setSmsGroupsResult(_ result: Result<[SmsGroup], Error>) {
        smsGroupsResult = result
    }

    // MARK: - APIClient conformance

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        lastGetPath = path

        // Server row list
        if T.self == [CampaignServerRow].self, path.contains("campaigns") && !path.contains("/") {
            return try campaignServerListResult.get() as! T
        }
        // Server row detail
        if T.self == CampaignServerRow.self {
            return try campaignServerGetResult.get() as! T
        }
        // Stats
        if T.self == CampaignStats.self {
            return try campaignStatsResult.get() as! T
        }
        // SMS Groups
        if T.self == [SmsGroup].self {
            return try smsGroupsResult.get() as! T
        }
        // Legacy
        if T.self == CampaignListResponse.self {
            return try campaignListResult.get() as! T
        }
        if T.self == Campaign.self {
            return try campaignGetResult.get() as! T
        }
        if T.self == CampaignReport.self {
            return try campaignReportResult.get() as! T
        }
        if T.self == SegmentListResponse.self {
            return try segmentListResult.get() as! T
        }
        if T.self == SegmentCountResponse.self {
            return try segmentCountResult.get() as! T
        }
        if T.self == ReferralCode.self {
            return try referralCodeResult.get() as! T
        }
        if T.self == ReferralLeaderboardResponse.self {
            return ReferralLeaderboardResponse(entries: []) as! T
        }
        if T.self == ReviewLastRequestResponse.self {
            return try reviewLastRequestResult.get() as! T
        }
        throw URLError(.unsupportedURL)
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        lastPostPath = path

        if path.contains("approve-send") {
            approveSendCalled += 1
            if case .failure(let e) = approveSendResult { throw e }
            let json = #"{"approved":true}"#
            return try JSONDecoder().decode(T.self, from: Data(json.utf8))
        }
        // Audience preview
        if T.self == CampaignAudiencePreview.self {
            audiencePreviewCalled += 1
            return try campaignAudiencePreviewResult.get() as! T
        }
        // Run now
        if T.self == CampaignRunNowResult.self {
            runNowCalled += 1
            return try campaignRunNowResult.get() as! T
        }
        // Server row create
        if T.self == CampaignServerRow.self {
            campaignServerCreateCalled += 1
            return try campaignServerCreateResult.get() as! T
        }
        if T.self == Campaign.self {
            if path.contains("/send") {
                sendCampaignCalled += 1
                return try campaignSendResult.get() as! T
            }
            createCampaignCalled += 1
            return try campaignCreateResult.get() as! T
        }
        if T.self == Segment.self {
            createSegmentCalled += 1
            return try segmentCreateResult.get() as! T
        }
        if T.self == SegmentCountResponse.self {
            previewCountCalled += 1
            return try previewCountResult.get() as! T
        }
        if T.self == ReferralRule.self {
            return try referralRuleResult.get() as! T
        }
        if T.self == ReviewRequestResponse.self {
            reviewRequestCalled += 1
            return try reviewRequestResult.get() as! T
        }
        if T.self == SurveySubmitResponse.self {
            if path.contains("csat") {
                csatSubmitCalled += 1
                return try csatSubmitResult.get() as! T
            } else {
                npsSubmitCalled += 1
                return try npsSubmitResult.get() as! T
            }
        }
        throw URLError(.unsupportedURL)
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw URLError(.unsupportedURL)
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        campaignServerPatchCalled += 1
        if T.self == CampaignServerRow.self {
            return try campaignServerPatchResult.get() as! T
        }
        throw URLError(.unsupportedURL)
    }

    func delete(_ path: String) async throws {
        if path.contains("campaigns") { campaignServerDeleteCalled += 1 }
    }

    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw URLError(.unsupportedURL)
    }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

// MARK: - Helpers for existing tests

extension MockAPIClient {
    func setCampaignCreateFail() async {
        campaignCreateResult = .failure(URLError(.badServerResponse))
    }
}
