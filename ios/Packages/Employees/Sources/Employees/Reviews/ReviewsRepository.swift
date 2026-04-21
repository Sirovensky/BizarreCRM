import Foundation
import Networking
import Core

// MARK: - ReviewsRepository

public protocol ReviewsRepository: Sendable {
    func listReviews(employeeId: String?) async throws -> [PerformanceReview]
    func createReview(_ req: CreateReviewRequest) async throws -> PerformanceReview
    func updateReview(id: String, _ req: UpdateReviewRequest) async throws -> PerformanceReview
    func deleteReview(id: String) async throws
}

// MARK: - ReviewsRepositoryImpl

public actor ReviewsRepositoryImpl: ReviewsRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func listReviews(employeeId: String?) async throws -> [PerformanceReview] {
        try await api.listReviews(employeeId: employeeId)
    }

    public func createReview(_ req: CreateReviewRequest) async throws -> PerformanceReview {
        try await api.createReview(req)
    }

    public func updateReview(id: String, _ req: UpdateReviewRequest) async throws -> PerformanceReview {
        try await api.updateReview(id: id, req)
    }

    public func deleteReview(id: String) async throws {
        try await api.deleteReview(id: id)
    }
}
