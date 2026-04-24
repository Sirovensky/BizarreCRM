import Foundation

// MARK: - Request / Response types

/// Envelope-level response shape for campaigns list from server.
/// The server returns rows directly (not cursor-paginated) from GET /campaigns.
/// Mirrors the DB row returned by `GET /campaigns` and `GET /campaigns/:id`.
/// APIClient uses `.convertFromSnakeCase` so camelCase properties map automatically.
public struct CampaignServerRow: Decodable, Sendable, Hashable {
    public let id: Int
    public let name: String
    public let type: String
    /// Mapped from `segment_id` via snake_case conversion.
    public let segmentId: Int?
    public let channel: String
    public let templateSubject: String?
    public let templateBody: String
    public let triggerRuleJson: String?
    public let status: String
    public let sentCount: Int
    public let repliedCount: Int
    public let convertedCount: Int
    public let createdAt: String
    public let lastRunAt: String?

    public init(
        id: Int, name: String, type: String, segmentId: Int?,
        channel: String, templateSubject: String?, templateBody: String,
        triggerRuleJson: String?, status: String,
        sentCount: Int, repliedCount: Int, convertedCount: Int,
        createdAt: String, lastRunAt: String?
    ) {
        self.id = id; self.name = name; self.type = type
        self.segmentId = segmentId; self.channel = channel
        self.templateSubject = templateSubject; self.templateBody = templateBody
        self.triggerRuleJson = triggerRuleJson; self.status = status
        self.sentCount = sentCount; self.repliedCount = repliedCount
        self.convertedCount = convertedCount; self.createdAt = createdAt
        self.lastRunAt = lastRunAt
    }
}

// Server returns { success, data: [...] } — array unwrapped directly by APIClient.

public struct CampaignAudiencePreview: Decodable, Sendable {
    public let campaignId: Int
    public let totalRecipients: Int
    public let preview: [PreviewRecipient]

    public init(campaignId: Int, totalRecipients: Int, preview: [PreviewRecipient]) {
        self.campaignId = campaignId
        self.totalRecipients = totalRecipients
        self.preview = preview
    }
}

public struct PreviewRecipient: Decodable, Sendable, Identifiable {
    public let customerId: Int
    public let firstName: String?
    public let renderedBody: String

    public var id: Int { customerId }

    public init(customerId: Int, firstName: String?, renderedBody: String) {
        self.customerId = customerId
        self.firstName = firstName
        self.renderedBody = renderedBody
    }
}

public struct CampaignStats: Decodable, Sendable {
    public let campaign: CampaignServerRow
    public let counts: CampaignStatCounts

    public init(campaign: CampaignServerRow, counts: CampaignStatCounts) {
        self.campaign = campaign
        self.counts = counts
    }
}

public struct CampaignStatCounts: Decodable, Sendable {
    public let sent: Int
    public let failed: Int
    public let replied: Int
    public let converted: Int

    public init(sent: Int, failed: Int, replied: Int, converted: Int) {
        self.sent = sent; self.failed = failed
        self.replied = replied; self.converted = converted
    }
}

public struct CampaignRunNowResult: Decodable, Sendable {
    public let attempted: Int
    public let sent: Int
    public let failed: Int
    public let skipped: Int

    public init(attempted: Int, sent: Int, failed: Int, skipped: Int) {
        self.attempted = attempted; self.sent = sent
        self.failed = failed; self.skipped = skipped
    }
}

public struct CreateCampaignServerRequest: Encodable, Sendable {
    public let name: String
    public let type: String
    public let channel: String
    public let templateBody: String
    public let templateSubject: String?
    public let segmentId: Int?
    public let triggerRuleJson: String?

    enum CodingKeys: String, CodingKey {
        case name, type, channel
        case templateBody = "template_body"
        case templateSubject = "template_subject"
        case segmentId = "segment_id"
        case triggerRuleJson = "trigger_rule_json"
    }

    public init(
        name: String, type: String, channel: String,
        templateBody: String, templateSubject: String? = nil,
        segmentId: Int? = nil, triggerRuleJson: String? = nil
    ) {
        self.name = name; self.type = type; self.channel = channel
        self.templateBody = templateBody; self.templateSubject = templateSubject
        self.segmentId = segmentId; self.triggerRuleJson = triggerRuleJson
    }
}

public struct PatchCampaignServerRequest: Encodable, Sendable {
    public let name: String?
    public let channel: String?
    public let status: String?
    public let templateBody: String?
    public let templateSubject: String?
    public let segmentId: Int?

    enum CodingKeys: String, CodingKey {
        case name, channel, status
        case templateBody = "template_body"
        case templateSubject = "template_subject"
        case segmentId = "segment_id"
    }

    public init(
        name: String? = nil, channel: String? = nil, status: String? = nil,
        templateBody: String? = nil, templateSubject: String? = nil, segmentId: Int? = nil
    ) {
        self.name = name; self.channel = channel; self.status = status
        self.templateBody = templateBody; self.templateSubject = templateSubject
        self.segmentId = segmentId
    }
}

// MARK: - SMS Groups (for audience picker)

/// SMS customer group from `GET /sms/groups`.
/// `.convertFromSnakeCase` maps `is_dynamic` → `isDynamic` and
/// `member_count_cache` → `memberCountCache` automatically.
public struct SmsGroup: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let description: String?
    public let isDynamic: Int      // server stores 0/1
    public let memberCountCache: Int

    public var isDynamicBool: Bool { isDynamic != 0 }

    public init(id: Int, name: String, description: String?,
                isDynamic: Int, memberCountCache: Int) {
        self.id = id; self.name = name; self.description = description
        self.isDynamic = isDynamic; self.memberCountCache = memberCountCache
    }
}

// MARK: - APIClient extension

private struct EmptyEncoding: Encodable, Sendable {}

public extension APIClient {

    // MARK: Campaigns (real server endpoints under /campaigns)

    func listCampaignsServer() async throws -> [CampaignServerRow] {
        try await get("campaigns", as: [CampaignServerRow].self)
    }

    func getCampaignServer(id: Int) async throws -> CampaignServerRow {
        try await get("campaigns/\(id)", as: CampaignServerRow.self)
    }

    func createCampaignServer(_ body: CreateCampaignServerRequest) async throws -> CampaignServerRow {
        try await post("campaigns", body: body, as: CampaignServerRow.self)
    }

    func patchCampaignServer(id: Int, _ body: PatchCampaignServerRequest) async throws -> CampaignServerRow {
        try await patch("campaigns/\(id)", body: body, as: CampaignServerRow.self)
    }

    func deleteCampaignServer(id: Int) async throws {
        try await delete("campaigns/\(id)")
    }

    func previewCampaignAudience(id: Int) async throws -> CampaignAudiencePreview {
        try await post("campaigns/\(id)/preview", body: EmptyEncoding(), as: CampaignAudiencePreview.self)
    }

    func runCampaignNow(id: Int) async throws -> CampaignRunNowResult {
        try await post("campaigns/\(id)/run-now", body: EmptyEncoding(), as: CampaignRunNowResult.self)
    }

    func getCampaignStats(id: Int) async throws -> CampaignStats {
        try await get("campaigns/\(id)/stats", as: CampaignStats.self)
    }

    // MARK: SMS Groups (for audience picker)

    // Note: sms/groups returns { success, data: [...] } — direct array unwrap.
    func listSmsGroups() async throws -> [SmsGroup] {
        try await get("sms/groups", as: [SmsGroup].self)
    }
}
