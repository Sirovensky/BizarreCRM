import Foundation
import Networking

// MARK: - APIClient + BulkSMS campaigns

/// §12.12 — Bulk SMS campaign endpoints.
///
/// Server routes (packages/server/src/routes/sms.routes.ts):
///   GET  /api/v1/sms/campaigns/preview?segment_key=&body=   → BulkCampaignPreview
///   POST /api/v1/sms/campaigns                               → BulkCampaignAck
///
/// TCPA: opted-out numbers filtered server-side.
/// Sovereignty: tenant server only.
public extension APIClient {

    /// Returns estimated recipient count + TCPA warning before sending.
    func previewBulkCampaign(
        segmentKey: String,
        body: String
    ) async throws -> BulkCampaignPreview {
        let query: [URLQueryItem] = [
            URLQueryItem(name: "segment_key", value: segmentKey),
            URLQueryItem(name: "body", value: body)
        ]
        return try await get("/api/v1/sms/campaigns/preview", query: query, as: BulkCampaignPreview.self)
    }

    /// Queues (or schedules) the campaign. Returns campaign ID + status.
    @discardableResult
    func sendBulkCampaign(_ request: BulkCampaignRequest) async throws -> BulkCampaignAck {
        try await post("/api/v1/sms/campaigns", body: request, as: BulkCampaignAck.self)
    }
}
