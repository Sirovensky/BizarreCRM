import Foundation
import Observation
import Core
import Networking

// §7.5 Invoice Void ViewModel — POST /api/v1/invoices/:id/void

public struct VoidRequest: Encodable, Sendable {
    public let reason: String
}

public struct VoidResult: Decodable, Sendable {
    public let id: Int64
    public let status: String?
}

@MainActor
@Observable
public final class InvoiceVoidViewModel {

    // MARK: - Form fields

    public var reason: String = ""

    // MARK: - State

    public enum State: Sendable {
        case idle
        case submitting
        case success(VoidResult)
        case failed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var fieldErrors: [String: String] = [:]

    @ObservationIgnored private let api: APIClient
    public let invoiceId: Int64
    /// Void is only allowed for invoices with zero payments or in draft state.
    public let canVoid: Bool

    public init(api: APIClient, invoiceId: Int64, canVoid: Bool) {
        self.api = api
        self.invoiceId = invoiceId
        self.canVoid = canVoid
    }

    // MARK: - Validation

    public var isValid: Bool {
        canVoid && !reason.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Submit

    public func submitVoid() async {
        guard canVoid else {
            state = .failed("Cannot void an invoice that has payments.")
            return
        }
        guard !reason.trimmingCharacters(in: .whitespaces).isEmpty else {
            state = .failed("A reason is required to void this invoice.")
            return
        }
        guard case .idle = state else { return }
        state = .submitting
        fieldErrors = [:]

        let body = VoidRequest(reason: reason)

        do {
            let result = try await api.post(
                "/api/v1/invoices/\(invoiceId)/void",
                body: body,
                as: VoidResult.self
            )
            state = .success(result)
        } catch {
            AppLog.ui.error("Void failed: \(error.localizedDescription, privacy: .public)")
            handleError(AppError.from(error))
        }
    }

    public func resetToIdle() {
        if case .failed = state { state = .idle }
    }

    // MARK: - Error mapping

    private func handleError(_ appError: AppError) {
        switch appError {
        case .validation(let errors):
            fieldErrors = errors
            state = .failed(errors.values.first ?? appError.errorDescription ?? "Validation error.")
        case .conflict:
            state = .failed("Invoice cannot be voided — it may have payments.")
        case .forbidden:
            state = .failed("You don't have permission to void invoices.")
        default:
            state = .failed(appError.errorDescription ?? "Void failed.")
        }
    }
}
