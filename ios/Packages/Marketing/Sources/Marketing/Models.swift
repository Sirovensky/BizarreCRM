import Foundation

// MARK: - Campaign

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
        report: CampaignReport? = nil
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
    }
}

public enum CampaignStatus: String, Codable, Sendable, CaseIterable {
    case draft, scheduled, sending, sent, failed

    public var displayName: String {
        switch self {
        case .draft:      return "Draft"
        case .scheduled:  return "Scheduled"
        case .sending:    return "Sending"
        case .sent:       return "Sent"
        case .failed:     return "Failed"
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
