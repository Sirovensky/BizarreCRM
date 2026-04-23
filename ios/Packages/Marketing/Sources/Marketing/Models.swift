import Foundation
import Networking

// MARK: - Campaign

/// Client-side campaign model used by ViewModels.
/// Built from `CampaignServerRow` via `Campaign.from(_:)`.
public struct Campaign: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var name: String
    public var status: CampaignStatus
    public var audienceSegmentId: String?
    public var template: String
    public var scheduledAt: Date?
    public var variantB: String?
    public var recipientsEstimate: Int?
    public var createdAt: Date
    public var report: CampaignReport?
    /// Server-aligned fields (populated when loading from real server)
    public var type: CampaignType
    public var channel: CampaignChannel
    public var templateSubject: String?
    public var sentCount: Int
    public var repliedCount: Int
    public var convertedCount: Int
    public var serverRowId: Int?  // numeric DB id, nil when using legacy string id

    public init(
        id: String,
        name: String,
        status: CampaignStatus,
        audienceSegmentId: String? = nil,
        template: String,
        scheduledAt: Date? = nil,
        variantB: String? = nil,
        recipientsEstimate: Int? = nil,
        createdAt: Date,
        report: CampaignReport? = nil,
        type: CampaignType = .custom,
        channel: CampaignChannel = .sms,
        templateSubject: String? = nil,
        sentCount: Int = 0,
        repliedCount: Int = 0,
        convertedCount: Int = 0,
        serverRowId: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.audienceSegmentId = audienceSegmentId
        self.template = template
        self.scheduledAt = scheduledAt
        self.variantB = variantB
        self.recipientsEstimate = recipientsEstimate
        self.createdAt = createdAt
        self.report = report
        self.type = type
        self.channel = channel
        self.templateSubject = templateSubject
        self.sentCount = sentCount
        self.repliedCount = repliedCount
        self.convertedCount = convertedCount
        self.serverRowId = serverRowId
    }

    /// Build a `Campaign` from the server row. Immutable — returns new value.
    public static func from(_ row: CampaignServerRow) -> Campaign {
        let status = CampaignStatus(rawValue: row.status) ?? .draft
        let type = CampaignType(rawValue: row.type) ?? .custom
        let channel = CampaignChannel(rawValue: row.channel) ?? .sms
        // Parse ISO 8601 date from string
        let formatter = ISO8601DateFormatter()
        let createdAt = formatter.date(from: row.createdAt) ?? Date()
        return Campaign(
            id: String(row.id),
            name: row.name,
            status: status,
            audienceSegmentId: row.segmentId.map { String($0) },
            template: row.templateBody,
            createdAt: createdAt,
            type: type,
            channel: channel,
            templateSubject: row.templateSubject,
            sentCount: row.sentCount,
            repliedCount: row.repliedCount,
            convertedCount: row.convertedCount,
            serverRowId: row.id
        )
    }
}

public enum CampaignStatus: String, Codable, Sendable, CaseIterable {
    case draft, active, paused, archived
    // Legacy display-only values (old model compat)
    case scheduled, sending, sent, failed

    public var displayName: String {
        switch self {
        case .draft:      return "Draft"
        case .active:     return "Active"
        case .paused:     return "Paused"
        case .archived:   return "Archived"
        case .scheduled:  return "Scheduled"
        case .sending:    return "Sending"
        case .sent:       return "Sent"
        case .failed:     return "Failed"
        }
    }

    /// Categories for the list filter tabs
    public static var activeCases: [CampaignStatus] { [.active, .sending] }
    public static var scheduledCases: [CampaignStatus] { [.scheduled, .draft] }
    public static var pastCases: [CampaignStatus] { [.sent, .archived, .paused, .failed] }
}

/// Matches `CAMPAIGN_TYPES` on the server.
public enum CampaignType: String, Codable, Sendable, CaseIterable {
    case birthday
    case winback
    case reviewRequest = "review_request"
    case churnWarning  = "churn_warning"
    case serviceSubscription = "service_subscription"
    case custom

    public var displayName: String {
        switch self {
        case .birthday:            return "Birthday"
        case .winback:             return "Win-back"
        case .reviewRequest:       return "Review Request"
        case .churnWarning:        return "Churn Warning"
        case .serviceSubscription: return "Service Subscription"
        case .custom:              return "Custom"
        }
    }

    public var systemImage: String {
        switch self {
        case .birthday:            return "gift.fill"
        case .winback:             return "arrow.counterclockwise.circle.fill"
        case .reviewRequest:       return "star.fill"
        case .churnWarning:        return "exclamationmark.triangle.fill"
        case .serviceSubscription: return "repeat.circle.fill"
        case .custom:              return "megaphone.fill"
        }
    }
}

/// Matches `CAMPAIGN_CHANNELS` on the server.
public enum CampaignChannel: String, Codable, Sendable, CaseIterable {
    case sms, email, both

    public var displayName: String {
        switch self {
        case .sms:   return "SMS"
        case .email: return "Email"
        case .both:  return "SMS + Email"
        }
    }

    public var systemImage: String {
        switch self {
        case .sms:   return "message.fill"
        case .email: return "envelope.fill"
        case .both:  return "square.and.arrow.up.fill"
        }
    }
}

public struct CampaignReport: Codable, Sendable, Hashable {
    public var delivered: Int
    public var failed: Int
    public var optedOut: Int
    public var replies: Int

    public init(delivered: Int, failed: Int, optedOut: Int, replies: Int) {
        self.delivered = delivered
        self.failed = failed
        self.optedOut = optedOut
        self.replies = replies
    }
}

// MARK: - Segment

public struct Segment: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var name: String
    public var rule: SegmentRuleGroup
    public var cachedCount: Int?

    public init(id: String, name: String, rule: SegmentRuleGroup, cachedCount: Int? = nil) {
        self.id = id
        self.name = name
        self.rule = rule
        self.cachedCount = cachedCount
    }
}

public indirect enum SegmentRule: Codable, Sendable, Hashable {
    case leaf(field: String, op: String, value: String)
    case group(SegmentRuleGroup)

    enum CodingKeys: String, CodingKey { case type, field, op, value, group }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type_ = try c.decode(String.self, forKey: .type)
        if type_ == "group" {
            let g = try c.decode(SegmentRuleGroup.self, forKey: .group)
            self = .group(g)
        } else {
            let f = try c.decode(String.self, forKey: .field)
            let o = try c.decode(String.self, forKey: .op)
            let v = try c.decode(String.self, forKey: .value)
            self = .leaf(field: f, op: o, value: v)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .leaf(let f, let o, let v):
            try c.encode("leaf", forKey: .type)
            try c.encode(f, forKey: .field)
            try c.encode(o, forKey: .op)
            try c.encode(v, forKey: .value)
        case .group(let g):
            try c.encode("group", forKey: .type)
            try c.encode(g, forKey: .group)
        }
    }
}

public struct SegmentRuleGroup: Codable, Sendable, Hashable {
    public var op: String // "AND" / "OR"
    public var rules: [SegmentRule]

    public init(op: String = "AND", rules: [SegmentRule] = []) {
        self.op = op
        self.rules = rules
    }
}

// MARK: - API request/response shapes

public struct CreateCampaignRequest: Encodable, Sendable {
    public var name: String
    public var audienceSegmentId: String?
    public var template: String
    public var scheduledAt: Date?
    public var variantB: String?

    public init(name: String, audienceSegmentId: String? = nil, template: String,
                scheduledAt: Date? = nil, variantB: String? = nil) {
        self.name = name
        self.audienceSegmentId = audienceSegmentId
        self.template = template
        self.scheduledAt = scheduledAt
        self.variantB = variantB
    }
}

// MARK: - Audience selection (segment or SMS group)

public enum AudienceSelection: Equatable, Sendable {
    case segment(id: String, name: String, count: Int)
    case smsGroup(id: Int, name: String, count: Int)
    case all

    public var displayName: String {
        switch self {
        case .segment(_, let name, _):  return name
        case .smsGroup(_, let name, _): return name
        case .all:                       return "All contacts"
        }
    }

    public var recipientCount: Int {
        switch self {
        case .segment(_, _, let c):  return c
        case .smsGroup(_, _, let c): return c
        case .all:                   return 0
        }
    }

    public var segmentIdString: String? {
        if case .segment(let id, _, _) = self { return id }
        return nil
    }

    public var smsGroupId: Int? {
        if case .smsGroup(let id, _, _) = self { return id }
        return nil
    }
}

// MARK: - Coupon code (inline CRUD)
// NOTE: No server endpoint exists for coupons at time of writing.
// This model is client-only until the server exposes a /coupons route.

public struct CouponCode: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var code: String
    public var discountType: CouponDiscountType
    public var discountValue: Double
    public var maxUses: Int?
    public var usedCount: Int
    public var expiresAt: Date?
    public var isActive: Bool

    public init(
        id: String,
        code: String,
        discountType: CouponDiscountType,
        discountValue: Double,
        maxUses: Int? = nil,
        usedCount: Int = 0,
        expiresAt: Date? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.code = code
        self.discountType = discountType
        self.discountValue = discountValue
        self.maxUses = maxUses
        self.usedCount = usedCount
        self.expiresAt = expiresAt
        self.isActive = isActive
    }

    public var displayDiscount: String {
        switch discountType {
        case .percent:   return "\(Int(discountValue))% off"
        case .fixedUSD:  return "$\(String(format: "%.2f", discountValue)) off"
        case .freeItem:  return "Free item"
        }
    }
}

public enum CouponDiscountType: String, Codable, Sendable, CaseIterable {
    case percent   = "percent"
    case fixedUSD  = "fixed_usd"
    case freeItem  = "free_item"

    public var displayName: String {
        switch self {
        case .percent:  return "% Discount"
        case .fixedUSD: return "$ Off"
        case .freeItem: return "Free Item"
        }
    }
}

public struct CreateSegmentRequest: Encodable, Sendable {
    public var name: String
    public var rule: SegmentRuleGroup

    public init(name: String, rule: SegmentRuleGroup) {
        self.name = name
        self.rule = rule
    }
}

public struct SegmentCountResponse: Decodable, Sendable {
    public var count: Int
}

public struct CampaignListResponse: Decodable, Sendable {
    public var campaigns: [Campaign]
    public var nextCursor: String?
}

public struct SegmentListResponse: Decodable, Sendable {
    public var segments: [Segment]
}
