import Foundation

// MARK: - BulkCampaignSegment

/// A named segment of customers selected for a bulk SMS campaign.
public enum BulkCampaignSegment: String, CaseIterable, Identifiable, Sendable {
    /// All opted-in customers (TCPA safe set).
    case all              = "all"
    /// Customers who haven't visited in 90+ days.
    case lapsed           = "lapsed"
    /// Customers with unpaid invoices.
    case unpaidInvoice    = "unpaid_invoice"
    /// Customers with upcoming appointments in the next 48h.
    case upcomingAppt     = "upcoming_appointment"
    /// Loyalty members only.
    case loyaltyMembers   = "loyalty_members"
    /// Custom segment (arbitrary customer_ids list supplied by caller).
    case custom           = "custom"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all:           return "All opted-in customers"
        case .lapsed:        return "Lapsed (90+ days)"
        case .unpaidInvoice: return "Unpaid invoice"
        case .upcomingAppt:  return "Upcoming appointment"
        case .loyaltyMembers: return "Loyalty members"
        case .custom:        return "Custom list"
        }
    }

    public var systemIcon: String {
        switch self {
        case .all:           return "person.3.fill"
        case .lapsed:        return "clock.badge.xmark"
        case .unpaidInvoice: return "dollarsign.circle.fill"
        case .upcomingAppt:  return "calendar.badge.clock"
        case .loyaltyMembers: return "star.fill"
        case .custom:        return "list.bullet"
        }
    }
}

// MARK: - BulkCampaignRequest

/// POST /api/v1/sms/campaigns — sends an SMS campaign to a named segment.
///
/// TCPA compliance check is performed server-side:
/// - Opted-out numbers are filtered automatically.
/// - STOP footer auto-appended by server if tenant has `auto_opt_out_footer` enabled.
/// - Caller should still display a preview of affected recipients before posting.
public struct BulkCampaignRequest: Encodable, Sendable {
    public let body: String
    public let segmentKey: String
    /// Used only when segmentKey == "custom".
    public let customerIds: [Int64]?
    public let scheduledAt: String?

    public init(
        body: String,
        segmentKey: String,
        customerIds: [Int64]? = nil,
        scheduledAt: String? = nil
    ) {
        self.body        = body
        self.segmentKey  = segmentKey
        self.customerIds = customerIds
        self.scheduledAt = scheduledAt
    }

    enum CodingKeys: String, CodingKey {
        case body
        case segmentKey  = "segment_key"
        case customerIds = "customer_ids"
        case scheduledAt = "scheduled_at"
    }
}

// MARK: - BulkCampaignPreview

/// GET /api/v1/sms/campaigns/preview — returns estimated recipient count and cost.
public struct BulkCampaignPreview: Decodable, Sendable {
    public let recipientCount: Int
    public let optedOutCount: Int
    public let estimatedSegments: Int
    public let tcpaWarning: String?

    enum CodingKeys: String, CodingKey {
        case recipientCount    = "recipient_count"
        case optedOutCount     = "opted_out_count"
        case estimatedSegments = "estimated_segments"
        case tcpaWarning       = "tcpa_warning"
    }
}

// MARK: - BulkCampaignAck

/// Response from POST /api/v1/sms/campaigns.
public struct BulkCampaignAck: Decodable, Sendable {
    public let campaignId: Int64
    public let recipientCount: Int
    public let status: String      // "queued" | "scheduled"

    enum CodingKeys: String, CodingKey {
        case campaignId    = "campaign_id"
        case recipientCount = "recipient_count"
        case status
    }
}
