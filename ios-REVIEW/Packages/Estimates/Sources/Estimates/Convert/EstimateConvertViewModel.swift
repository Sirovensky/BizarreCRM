import Foundation
import Observation
import Core
import Networking

// MARK: - EstimateConvertViewModel

/// VM for converting an estimate to a ticket.
/// Calls `POST /estimates/:id/convert-to-ticket`.
@MainActor
@Observable
public final class EstimateConvertViewModel {

    // MARK: - Input

    /// The estimate being converted.
    public let estimate: Estimate

    // MARK: - Output state

    public private(set) var isConverting: Bool = false
    public private(set) var errorMessage: String?
    /// Set on success; observer should dismiss + navigate.
    public private(set) var createdTicketId: Int64?

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient
    /// Called with the new ticketId on success so the caller can navigate.
    @ObservationIgnored private let onSuccess: @MainActor (Int64) -> Void

    // MARK: - Init

    public init(
        estimate: Estimate,
        api: APIClient,
        onSuccess: @escaping @MainActor (Int64) -> Void = { _ in }
    ) {
        self.estimate = estimate
        self.api = api
        self.onSuccess = onSuccess
    }

    // MARK: - Computed helpers

    public var customerName: String { estimate.customerName }
    public var totalFormatted: String { Self.formatMoney(estimate.total ?? 0) }
    public var orderId: String { estimate.orderId ?? "EST-?" }

    // MARK: - Computed helpers (version approval)

    /// §8 — True when the customer approved a specific version that is older than
    /// the current draft. The convert sheet should show which version will be used.
    public var isConvertingApprovedVersion: Bool {
        guard let approved = estimate.approvedVersionNumber,
              let current = estimate.versionNumber else { return false }
        return current > approved
    }

    /// §8 — The version number that will be used for conversion (the approved one,
    /// not necessarily the latest).
    public var convertVersionLabel: String {
        if let approved = estimate.approvedVersionNumber {
            return "v\(approved)"
        }
        if let current = estimate.versionNumber {
            return "v\(current)"
        }
        return "latest"
    }

    // MARK: - Actions

    public func convert() async {
        guard !isConverting else { return }
        isConverting = true
        errorMessage = nil
        defer { isConverting = false }

        do {
            // §8 — Use the approved version number as reference so downstream
            //        edits to the estimate don't invalidate the created ticket.
            let result = try await api.convertEstimateToTicketWithVersion(
                estimateId: estimate.id,
                approvedVersionId: estimate.approvedVersionNumber.map { Int64($0) }
            )
            createdTicketId = result.ticketId
            onSuccess(result.ticketId)
        } catch {
            let appError = Self.mapError(error)
            errorMessage = Self.message(for: appError)
            AppLog.ui.error(
                "Estimate convert failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Private helpers

    /// Maps `APITransportError.httpStatus` to the richer `AppError` taxonomy
    /// so callers can match named cases like `.conflict`, `.notFound`, etc.
    private static func mapError(_ error: Error) -> AppError {
        if let transportErr = error as? APITransportError,
           case .httpStatus(let code, let msg) = transportErr {
            return AppError.fromHttp(statusCode: code, message: msg)
        }
        return AppError.from(error)
    }

    private static func message(for error: AppError) -> String {
        switch error {
        case .conflict:
            return "This estimate has already been converted to a ticket."
        case .validation(let fields):
            return fields.values.first ?? "Validation failed — check estimate details."
        case .notFound:
            return "Estimate not found. It may have been deleted."
        case .offline:
            return "You're offline. Connect and try again."
        default:
            return error.errorDescription ?? "An unexpected error occurred."
        }
    }

    private static func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}
