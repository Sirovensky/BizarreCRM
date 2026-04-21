import Foundation
import Networking
@testable import Marketing

// Top-level types for mock use (Swift 6: no nested types in generic functions)
private struct MockApproveResponse: Decodable, Sendable { let approved: Bool? }

/// Minimal mock APIClient for unit tests. Sendable-safe via actors.
actor MockAPIClient: APIClient {
    // Configurable stubs
    var campaignListResult: Result<CampaignListResponse, Error> = .success(CampaignListResponse(campaigns: [], nextCursor: nil))
    var campaignCreateResult: Result<Campaign, Error> = .success(Campaign(id: "1", name: "Test", status: .draft, template: "Hello", createdAt: Date()))
    var campaignGetResult: Result<Campaign, Error> = .success(Campaign(id: "1", name: "Test", status: .draft, template: "Hello", createdAt: Date()))
    var campaignSendResult: Result<Campaign, Error> = .success(Campaign(id: "1", name: "Test", status: .sending, template: "Hello", createdAt: Date()))
    var campaignReportResult: Result<CampaignReport, Error> = .success(CampaignReport(delivered: 10, failed: 1, optedOut: 0, replies: 2))
    var approveSendResult: Result<Void, Error> = .success(())
    var segmentListResult: Result<SegmentListResponse, Error> = .success(SegmentListResponse(segments: []))
    var segmentCreateResult: Result<Segment, Error> = .success(Segment(id: "s1", name: "Test", rule: SegmentRuleGroup(), cachedCount: 0))
    var segmentCountResult: Result<SegmentCountResponse, Error> = .success(SegmentCountResponse(count: 42))
    var previewCountResult: Result<SegmentCountResponse, Error> = .success(SegmentCountResponse(count: 17))

    // Call counts for verification
    var createCampaignCalled = 0
    var sendCampaignCalled = 0
    var createSegmentCalled = 0
    var previewCountCalled = 0
    var approveSendCalled = 0

    // MARK: - APIClient conformance

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
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
        throw URLError(.unsupportedURL)
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if path.contains("approve-send") {
            approveSendCalled += 1
            if case .failure(let e) = approveSendResult { throw e }
            // Encode/decode a valid JSON response for the generic return type
            let json = #"{"approved":true}"#
            let data = Data(json.utf8)
            return try JSONDecoder().decode(T.self, from: data)
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
        throw URLError(.unsupportedURL)
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw URLError(.unsupportedURL)
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw URLError(.unsupportedURL)
    }

    func delete(_ path: String) async throws {}

    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw URLError(.unsupportedURL)
    }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
