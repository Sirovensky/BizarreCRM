import Testing
import Foundation
@testable import Marketing

@Suite("ReviewSolicitationService")
struct ReviewSolicitationServiceTests {

    // MARK: - Rate limiting

    @Test("sendReviewRequest succeeds when customer has no prior request")
    func sendsWhenNoPrior() async throws {
        let mock = MockAPIClient()
        await mock.setReviewLastRequestResult(.success(ReviewLastRequestResponse(lastRequestedAt: nil)))
        let service = ReviewSolicitationService(api: mock)
        try await service.sendReviewRequest(customerId: "c1", platform: .google)
        let count = await mock.reviewRequestCalled
        #expect(count == 1)
    }

    @Test("sendReviewRequest blocked within 180 days")
    func blockedWithin180Days() async {
        let mock = MockAPIClient()
        let recent = Date().addingTimeInterval(-86400 * 30) // 30 days ago
        await mock.setReviewLastRequestResult(.success(ReviewLastRequestResponse(lastRequestedAt: recent)))
        let service = ReviewSolicitationService(api: mock)
        do {
            try await service.sendReviewRequest(customerId: "c1", platform: nil)
            Issue.record("Expected rate-limit error")
        } catch ReviewSolicitationError.rateLimited(let daysRemaining) {
            #expect(daysRemaining > 0)
            #expect(daysRemaining < 180)
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test("sendReviewRequest allowed after 180 days")
    func allowedAfter180Days() async throws {
        let mock = MockAPIClient()
        let oldRequest = Date().addingTimeInterval(-86400 * 181) // 181 days ago
        await mock.setReviewLastRequestResult(.success(ReviewLastRequestResponse(lastRequestedAt: oldRequest)))
        let service = ReviewSolicitationService(api: mock)
        try await service.sendReviewRequest(customerId: "c1", platform: .yelp)
        let count = await mock.reviewRequestCalled
        #expect(count == 1)
    }

    @Test("sendReviewRequest exactly at 180 days is blocked")
    func exactlyAt180DaysBlocked() async {
        let mock = MockAPIClient()
        let exactly180 = Date().addingTimeInterval(-86400 * 180)
        await mock.setReviewLastRequestResult(.success(ReviewLastRequestResponse(lastRequestedAt: exactly180)))
        let service = ReviewSolicitationService(api: mock)
        do {
            try await service.sendReviewRequest(customerId: "c1", platform: nil)
            Issue.record("Expected rate-limit error")
        } catch ReviewSolicitationError.rateLimited {
            // correct
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }

    @Test("sendReviewRequest posts to correct API path")
    func sendsToCorrectPath() async throws {
        let mock = MockAPIClient()
        await mock.setReviewLastRequestResult(.success(ReviewLastRequestResponse(lastRequestedAt: nil)))
        let service = ReviewSolicitationService(api: mock)
        try await service.sendReviewRequest(customerId: "cust42", platform: .google)
        let path = await mock.lastPostPath
        #expect(path == "reviews/request")
    }

    @Test("API failure propagates")
    func apiFailurePropagates() async {
        let mock = MockAPIClient()
        await mock.setReviewLastRequestResult(.success(ReviewLastRequestResponse(lastRequestedAt: nil)))
        await mock.setReviewRequestResult(.failure(URLError(.timedOut)))
        let service = ReviewSolicitationService(api: mock)
        do {
            try await service.sendReviewRequest(customerId: "c1", platform: nil)
            Issue.record("Expected error")
        } catch {
            #expect(error is URLError)
        }
    }
}
