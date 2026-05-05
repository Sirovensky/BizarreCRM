import XCTest
@testable import Employees
import Networking

// MARK: - MockReviewsRepository

final class MockReviewsRepository: ReviewsRepository, @unchecked Sendable {
    var stubbedReviews: [PerformanceReview] = []
    var shouldThrow = false
    var updatedRequests: [(String, UpdateReviewRequest)] = []

    func listReviews(employeeId: String?) async throws -> [PerformanceReview] {
        if shouldThrow { throw NSError(domain: "test", code: 1) }
        return stubbedReviews
    }

    func createReview(_ req: CreateReviewRequest) async throws -> PerformanceReview {
        if shouldThrow { throw NSError(domain: "test", code: 1) }
        return PerformanceReview(id: "new", employeeId: req.employeeId,
                                 periodStart: req.periodStart, periodEnd: req.periodEnd)
    }

    func updateReview(id: String, _ req: UpdateReviewRequest) async throws -> PerformanceReview {
        if shouldThrow { throw NSError(domain: "test", code: 1) }
        updatedRequests.append((id, req))
        let base = stubbedReviews.first { $0.id == id } ??
            PerformanceReview(id: id, employeeId: "e1",
                              periodStart: Date(), periodEnd: Date().addingTimeInterval(86400))
        return base
    }

    func deleteReview(id: String) async throws {
        if shouldThrow { throw NSError(domain: "test", code: 1) }
    }
}

// MARK: - PerformanceReviewComposeViewModelTests

@MainActor
final class PerformanceReviewComposeViewModelTests: XCTestCase {

    private func makeReview(id: String = "r1") -> PerformanceReview {
        PerformanceReview(
            id: id, employeeId: "emp1",
            periodStart: Date(),
            periodEnd: Date().addingTimeInterval(86400 * 90)
        )
    }

    func test_save_callsUpdate() async {
        let repo = MockReviewsRepository()
        var saved: PerformanceReview?
        let vm = PerformanceReviewComposeViewModel(repo: repo, review: makeReview()) { r in
            saved = r
        }
        vm.managerDraft = "Great performance."
        await vm.save()
        XCTAssertNotNil(saved)
        XCTAssertEqual(repo.updatedRequests.count, 1)
    }

    func test_save_failsOnEmptyDraft() async {
        let repo = MockReviewsRepository()
        let vm = PerformanceReviewComposeViewModel(repo: repo, review: makeReview()) { _ in }
        vm.managerDraft = ""
        await vm.save()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(repo.updatedRequests.isEmpty)
    }

    func test_setScore_updatesRating() {
        let repo = MockReviewsRepository()
        let vm = PerformanceReviewComposeViewModel(repo: repo, review: makeReview()) { _ in }
        vm.setScore(for: .customerService, score: 5)
        let rating = vm.competencyRatings.first { $0.competency == .customerService }
        XCTAssertEqual(rating?.score, 5)
    }

    func test_competencyRatings_allCompetenciesPresent() {
        let repo = MockReviewsRepository()
        let vm = PerformanceReviewComposeViewModel(repo: repo, review: makeReview()) { _ in }
        let allCompetencies = Set(Competency.allCases.map { $0.rawValue })
        let presentCompetencies = Set(vm.competencyRatings.map { $0.competency.rawValue })
        XCTAssertEqual(allCompetencies, presentCompetencies)
    }

    func test_averageCompetencyScore() {
        let review = PerformanceReview(
            id: "r2", employeeId: "e2",
            periodStart: Date(), periodEnd: Date(),
            competencyRatings: [
                CompetencyRating(competency: .customerService, score: 4),
                CompetencyRating(competency: .technicalSkill, score: 3)
            ]
        )
        XCTAssertEqual(review.averageCompetencyScore ?? 0, 3.5, accuracy: 0.01)
    }

    func test_averageCompetencyScore_noRatings_returnsNil() {
        let review = makeReview()
        XCTAssertNil(review.averageCompetencyScore)
    }
}

// MARK: - SelfReviewViewModelTests

@MainActor
final class SelfReviewViewModelTests: XCTestCase {

    func test_save_requiresStrengths() async {
        let repo = MockReviewsRepository()
        let review = PerformanceReview(id: "r1", employeeId: "e1",
                                       periodStart: Date(), periodEnd: Date())
        let vm = SelfReviewViewModel(repo: repo, review: review) { _ in }
        vm.strengths = ""
        await vm.save()
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_save_successWithStrengths() async {
        let repo = MockReviewsRepository()
        let review = PerformanceReview(id: "r1", employeeId: "e1",
                                       periodStart: Date(), periodEnd: Date())
        var called = false
        let vm = SelfReviewViewModel(repo: repo, review: review) { _ in called = true }
        vm.strengths = "Great communicator"
        await vm.save()
        XCTAssertTrue(called)
        XCTAssertNil(vm.errorMessage)
    }
}
