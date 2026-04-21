import Foundation
import Networking

// MARK: - Response containers

public struct ReviewsListResponse: Decodable, Sendable {
    public let reviews: [PerformanceReview]
}

public struct ReviewResponse: Decodable, Sendable {
    public let review: PerformanceReview
}

// MARK: - Request bodies

public struct CreateReviewRequest: Encodable, Sendable {
    public let employeeId: String
    public let periodStart: Date
    public let periodEnd: Date

    enum CodingKeys: String, CodingKey {
        case employeeId  = "employee_id"
        case periodStart = "period_start"
        case periodEnd   = "period_end"
    }
}

public struct UpdateReviewRequest: Encodable, Sendable {
    public let managerDraft: String?
    public let selfReview: String?
    public let competencyRatings: [CompetencyRating]?
    public let finalScore: Double?
    public let acknowledgement: String?
    public let status: ReviewStatus?

    public init(
        managerDraft: String? = nil,
        selfReview: String? = nil,
        competencyRatings: [CompetencyRating]? = nil,
        finalScore: Double? = nil,
        acknowledgement: String? = nil,
        status: ReviewStatus? = nil
    ) {
        self.managerDraft = managerDraft
        self.selfReview = selfReview
        self.competencyRatings = competencyRatings
        self.finalScore = finalScore
        self.acknowledgement = acknowledgement
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case managerDraft      = "manager_draft"
        case selfReview        = "self_review"
        case competencyRatings = "competency_ratings"
        case finalScore        = "final_score"
        case acknowledgement
        case status
    }
}

// MARK: - APIClient extensions

public extension APIClient {
    func listReviews(employeeId: String? = nil) async throws -> [PerformanceReview] {
        var query: [URLQueryItem] = []
        if let eid = employeeId { query.append(.init(name: "employee_id", value: eid)) }
        return try await get("/employees/reviews",
                             query: query.isEmpty ? nil : query,
                             as: ReviewsListResponse.self).reviews
    }

    func createReview(_ req: CreateReviewRequest) async throws -> PerformanceReview {
        try await post("/employees/reviews", body: req, as: ReviewResponse.self).review
    }

    func updateReview(id: String, _ req: UpdateReviewRequest) async throws -> PerformanceReview {
        try await patch("/employees/reviews/\(id)", body: req, as: ReviewResponse.self).review
    }

    func deleteReview(id: String) async throws {
        try await delete("/employees/reviews/\(id)")
    }
}
