import Foundation

// MARK: - ReviewStatus

public enum ReviewStatus: String, Codable, CaseIterable, Sendable {
    case draft        = "draft"
    case selfPending  = "self_pending"
    case peerPending  = "peer_pending"
    case managerReady = "manager_ready"
    case acknowledged = "acknowledged"
    case disputed     = "disputed"
}

// MARK: - CompetencyRating

public struct CompetencyRating: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public var competency: Competency
    public var score: Int          // 1–5

    public init(competency: Competency, score: Int) {
        self.id = competency.rawValue
        self.competency = competency
        self.score = max(1, min(5, score))
    }
}

public enum Competency: String, Codable, CaseIterable, Sendable {
    case customerService  = "customer_service"
    case technicalSkill   = "technical_skill"
    case teamwork         = "teamwork"
    case initiative       = "initiative"
    case quality          = "quality"

    public var displayName: String {
        switch self {
        case .customerService: return "Customer Service"
        case .technicalSkill:  return "Technical Skill"
        case .teamwork:        return "Teamwork"
        case .initiative:      return "Initiative"
        case .quality:         return "Quality"
        }
    }
}

// MARK: - PeerFeedbackSummary

public struct PeerFeedbackSummary: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public var feedbackText: String
    public var isAnonymous: Bool

    public init(id: String, feedbackText: String, isAnonymous: Bool = true) {
        self.id = id
        self.feedbackText = feedbackText
        self.isAnonymous = isAnonymous
    }

    enum CodingKeys: String, CodingKey {
        case id, feedbackText = "feedback_text", isAnonymous = "is_anonymous"
    }
}

// MARK: - PerformanceReview

public struct PerformanceReview: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public var employeeId: String
    public var periodStart: Date
    public var periodEnd: Date
    public var managerDraft: String
    public var selfReview: String
    public var peerFeedback: [PeerFeedbackSummary]
    public var competencyRatings: [CompetencyRating]
    public var finalScore: Double?
    public var acknowledgement: String?   // base64 signature PNG or nil
    public var status: ReviewStatus

    public init(
        id: String,
        employeeId: String,
        periodStart: Date,
        periodEnd: Date,
        managerDraft: String = "",
        selfReview: String = "",
        peerFeedback: [PeerFeedbackSummary] = [],
        competencyRatings: [CompetencyRating] = [],
        finalScore: Double? = nil,
        acknowledgement: String? = nil,
        status: ReviewStatus = .draft
    ) {
        self.id = id
        self.employeeId = employeeId
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.managerDraft = managerDraft
        self.selfReview = selfReview
        self.peerFeedback = peerFeedback
        self.competencyRatings = competencyRatings
        self.finalScore = finalScore
        self.acknowledgement = acknowledgement
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case id, status
        case employeeId        = "employee_id"
        case periodStart       = "period_start"
        case periodEnd         = "period_end"
        case managerDraft      = "manager_draft"
        case selfReview        = "self_review"
        case peerFeedback      = "peer_feedback"
        case competencyRatings = "competency_ratings"
        case finalScore        = "final_score"
        case acknowledgement
    }

    /// Average of competency scores (1–5). Returns nil when no ratings.
    public var averageCompetencyScore: Double? {
        guard !competencyRatings.isEmpty else { return nil }
        let sum = competencyRatings.reduce(0) { $0 + $1.score }
        return Double(sum) / Double(competencyRatings.count)
    }
}
