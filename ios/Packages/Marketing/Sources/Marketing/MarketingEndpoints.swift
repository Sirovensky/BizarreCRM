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
}
