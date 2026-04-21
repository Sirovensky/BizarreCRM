import Foundation
import Networking

// MARK: - ReviewSolicitationError

public enum ReviewSolicitationError: Error, Sendable {
    /// Customer was asked within the last `daysRemaining` days — wait before re-asking.
    case rateLimited(daysRemaining: Int)
}

// MARK: - ReviewSolicitationService

public actor ReviewSolicitationService {
    /// Number of days the rate-limit window spans.
    public static let rateLimitDays = 180

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Public interface

    /// Send a review request to a customer.
    ///
    /// - Throws: `ReviewSolicitationError.rateLimited` if the customer was asked
    ///   within the last 180 days. Throws an `Error` from the network layer on failure.
    public func sendReviewRequest(customerId: String, platform: ReviewPlatform?) async throws {
        // 1. Rate-limit check
        let lastRequest = try await api.get(
            "reviews/last-request/\(customerId)",
            as: ReviewLastRequestResponse.self
        )

        if let lastDate = lastRequest.lastRequestedAt {
            let daysSince = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
            // Block if strictly less than 180 days have elapsed (>180 required, not ≥180)
            if daysSince <= Self.rateLimitDays {
                let remaining = Self.rateLimitDays - daysSince + 1
                throw ReviewSolicitationError.rateLimited(daysRemaining: remaining)
            }
        }

        // 2. Build template
        let template = defaultTemplate(for: platform)
        let body = ReviewRequestBody(customerId: customerId, platform: platform, template: template)

        // 3. POST
        _ = try await api.post("reviews/request", body: body, as: ReviewRequestResponse.self)
    }

    // MARK: - Helpers

    private func defaultTemplate(for platform: ReviewPlatform?) -> String {
        let platformName = platform?.displayName ?? "us"
        return "Hi! We hope you enjoyed your visit. Would you mind leaving us a review on \(platformName)? It only takes a minute and means a lot to us. Thank you!"
    }
}
