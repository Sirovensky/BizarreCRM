import Foundation
import Observation
import Core
import Networking

// §8 Sign flow — EstimateSignViewModel
// Issues a customer e-sign URL via POST /api/v1/estimates/:id/sign-url.
// The URL is surfaced to staff who can copy it or hand the device to the customer.

@MainActor
@Observable
public final class EstimateSignViewModel {

    // MARK: - Inputs

    /// Optional override in minutes. Nil = server default (3 days).
    public var ttlMinutes: Int? = nil

    // MARK: - Output state

    public private(set) var isIssuing: Bool = false
    public private(set) var signUrl: String?
    public private(set) var expiresAt: String?
    public private(set) var errorMessage: String?

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let estimateId: Int64

    // MARK: - Init

    public init(estimateId: Int64, api: APIClient) {
        self.estimateId = estimateId
        self.api = api
    }

    // MARK: - Actions

    public func issueSignUrl() async {
        guard !isIssuing else { return }
        isIssuing = true
        errorMessage = nil
        signUrl = nil
        expiresAt = nil
        defer { isIssuing = false }

        do {
            let response = try await api.issueEstimateSignUrl(
                estimateId: estimateId,
                ttlMinutes: ttlMinutes
            )
            signUrl = response.url
            expiresAt = response.expiresAt
        } catch {
            let appError = Self.mapError(error)
            errorMessage = Self.message(for: appError)
            AppLog.ui.error(
                "EstimateSign issue failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Helpers

    private static func mapError(_ error: Error) -> AppError {
        if let transportErr = error as? APITransportError,
           case .httpStatus(let code, let msg) = transportErr {
            return AppError.fromHttp(statusCode: code, message: msg)
        }
        return AppError.from(error)
    }

    private static func message(for error: AppError) -> String {
        switch error {
        case .forbidden:
            return "You need admin or manager access to issue sign links."
        case .conflict:
            return "This estimate is already signed."
        case .notFound:
            return "Estimate not found. It may have been deleted."
        case .offline:
            return "You're offline. Connect and try again."
        case .rateLimited(let retryAfterSeconds):
            let seconds = retryAfterSeconds ?? 60
            return "Too many sign links issued. Try again in \(seconds)s."
        default:
            return error.errorDescription ?? "Failed to issue sign link."
        }
    }
}
