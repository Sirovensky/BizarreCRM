import Foundation

// MARK: - LTVTrend

/// Direction of a customer's lifetime value over recent activity.
public enum LTVTrend: String, Sendable, Equatable, Codable, CaseIterable {
    case growing
    case stable
    case declining
}

// MARK: - ChurnInput

/// Structured input for `ChurnScoreCalculator.compute(input:)`.
///
/// All fields are optional — nil means "no data available" and the
/// calculator ignores that factor (no penalty, no bonus).
public struct ChurnInput: Sendable, Equatable {
    /// Days elapsed since the customer's last visit. nil = unknown.
    public let daysSinceLastVisit: Int?
    /// Whether visit frequency has noticeably declined.
    public let visitFrequencyDecline: Bool
    /// Number of open support complaints on record.
    public let supportComplaints: Int
    /// Net Promoter Score 0–10 (detractor ≤ 6). nil = not surveyed.
    public let npsScore: Int?
    /// Direction of customer's LTV over recent activity.
    public let ltvTrend: LTVTrend

    public init(
        daysSinceLastVisit: Int?,
        visitFrequencyDecline: Bool,
        supportComplaints: Int,
        npsScore: Int?,
        ltvTrend: LTVTrend
    ) {
        self.daysSinceLastVisit   = daysSinceLastVisit
        self.visitFrequencyDecline = visitFrequencyDecline
        self.supportComplaints    = supportComplaints
        self.npsScore             = npsScore
        self.ltvTrend             = ltvTrend
    }
}

// MARK: - ChurnScore

/// The output of `ChurnScoreCalculator.compute(input:)`.
///
/// `probability0to100` is the client-side estimate.
/// The server score (if available) should override this — see `ChurnEndpoints`.
public struct ChurnScore: Sendable, Equatable {
    public let customerId:         Int64?
    /// 0–100 churn probability (higher = more likely to churn).
    public let probability0to100:  Int
    public let computedAt:         Date
    /// Human-readable factor descriptions explaining the score.
    public let factors:            [String]
    public let riskLevel:          ChurnRiskLevel

    public init(
        customerId: Int64? = nil,
        probability0to100: Int,
        computedAt: Date = Date(),
        factors: [String],
        riskLevel: ChurnRiskLevel
    ) {
        self.customerId        = customerId
        self.probability0to100 = max(0, min(100, probability0to100))
        self.computedAt        = computedAt
        self.factors           = factors
        self.riskLevel         = riskLevel
    }
}

// MARK: - ChurnScoreDTO (server response)

/// `GET /customers/:id/churn-score` response envelope data.
public struct ChurnScoreDTO: Decodable, Sendable {
    public let customerId:        Int64
    public let probability:       Int
    public let factors:           [String]
    public let riskLevel:         String
    public let computedAt:        String

    enum CodingKeys: String, CodingKey {
        case customerId  = "customer_id"
        case probability
        case factors
        case riskLevel   = "risk_level"
        case computedAt  = "computed_at"
    }

    public func toChurnScore() -> ChurnScore {
        let risk = ChurnRiskLevel(rawValue: riskLevel) ?? ChurnRiskLevel(probability: probability)
        let date = ISO8601DateFormatter().date(from: computedAt) ?? Date()
        return ChurnScore(
            customerId:        customerId,
            probability0to100: probability,
            computedAt:        date,
            factors:           factors,
            riskLevel:         risk
        )
    }
}

// MARK: - ChurnCohortDTO

/// `GET /customers/churn-cohort?riskLevel=high` response.
public struct ChurnCohortDTO: Decodable, Sendable {
    public let customers: [ChurnCohortEntry]

    public struct ChurnCohortEntry: Decodable, Sendable, Identifiable {
        public let id: Int64
        public let customerId: Int64
        public let customerName: String
        public let probability: Int
        public let riskLevel: String
        public let topFactor: String?

        enum CodingKeys: String, CodingKey {
            case id
            case customerId   = "customer_id"
            case customerName = "customer_name"
            case probability
            case riskLevel    = "risk_level"
            case topFactor    = "top_factor"
        }

        public var churnRiskLevel: ChurnRiskLevel {
            ChurnRiskLevel(rawValue: riskLevel) ?? ChurnRiskLevel(probability: probability)
        }
    }
}
