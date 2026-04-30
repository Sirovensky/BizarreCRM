import Foundation
import Observation
import Core
import Networking

// §7.7 Customer return flow ViewModel
// Endpoint: POST /api/v1/refunds (existing route, extended with `lines` field)
// Fraud guard: warn if total refund > $200 (kReturnManagerPinThresholdCents); require manager PIN.
// No BlockChyp path — hardware tenders deferred to Agent-2.
// Audit: every return submission creates a server-side audit log entry (server enforced).

@MainActor
@Observable
public final class InvoiceReturnViewModel {

    // MARK: - Form state

    public var lines: [InvoiceReturnLine]
    public var selectedTender: ReturnTender = .cash
    public var returnReason: String = ""
    public var managerPin: String = ""
    public var showManagerPinPrompt: Bool = false
    public var showFraudWarning: Bool = false

    // MARK: - Restocking fee

    /// Loaded from server; nil = no fee policy active.
    public var restockingFeePolicy: RestockingFeePolicy?
    public var daysSincePurchase: Int = 0

    // MARK: - State machine

    public enum State: Sendable, Equatable {
        case idle
        case submitting
        case success(refundId: Int64)
        case failed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var fieldErrors: [String: String] = [:]

    @ObservationIgnored private let api: APIClient
    public let invoiceId: Int64
    public let customerId: Int64

    public init(
        api: APIClient,
        invoiceId: Int64,
        customerId: Int64,
        lines: [InvoiceReturnLine],
        restockingFeePolicy: RestockingFeePolicy? = nil,
        daysSincePurchase: Int = 0
    ) {
        self.api = api
        self.invoiceId = invoiceId
        self.customerId = customerId
        self.lines = lines
        self.restockingFeePolicy = restockingFeePolicy
        self.daysSincePurchase = daysSincePurchase
    }

    // MARK: - Computed

    /// Lines the user has selected for return.
    public var selectedLines: [InvoiceReturnLine] {
        lines.filter(\.isSelected)
    }

    /// Gross refund (before restocking fee) in cents.
    public var grossRefundCents: Int {
        selectedLines.reduce(0) { $0 + $1.grossRefundCents }
    }

    /// Total restocking fee in cents across all selected lines.
    public var totalRestockingFeeCents: Int {
        guard let policy = restockingFeePolicy else { return 0 }
        return selectedLines.reduce(0) { total, line in
            total + policy.fee(
                grossCents: line.grossRefundCents,
                qtyReturned: line.qtyToReturn,
                daysSincePurchase: daysSincePurchase
            )
        }
    }

    /// Net refund in cents (gross minus restocking fee).
    public var netRefundCents: Int {
        max(0, grossRefundCents - totalRestockingFeeCents)
    }

    /// Whether the net refund amount exceeds the fraud warning threshold.
    public var exceedsFraudThreshold: Bool {
        netRefundCents > kReturnManagerPinThresholdCents
    }

    /// Manager PIN is required when refund exceeds the threshold.
    public var requiresManagerPin: Bool { exceedsFraudThreshold }

    /// Form is valid when at least one line is selected and reason is present.
    public var isValid: Bool {
        !selectedLines.isEmpty && !returnReason.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Submit

    public func submitReturn() async {
        guard isValid else {
            state = .failed("Select at least one item and provide a return reason.")
            return
        }
        // Show fraud warning on first attempt if threshold exceeded and no PIN yet.
        if exceedsFraudThreshold && managerPin.isEmpty {
            showFraudWarning = true
            return
        }
        guard case .idle = state else { return }
        state = .submitting
        fieldErrors = [:]

        let linesBodies = selectedLines.map { line in
            InvoiceReturnRequest.ReturnLineBody(
                lineItemId: line.id,
                qty: line.qtyToReturn,
                disposition: line.disposition.rawValue
            )
        }
        let amountDollars = Double(netRefundCents) / 100.0
        let body = InvoiceReturnRequest(
            invoiceId: invoiceId,
            customerId: customerId,
            amount: amountDollars,
            method: selectedTender.rawValue,
            reason: returnReason.trimmingCharacters(in: .whitespaces),
            lines: linesBodies
        )

        do {
            let result = try await api.createReturnRefund(body: body)
            state = .success(refundId: result.id)
        } catch {
            AppLog.ui.error("Invoice return submission failed: \(error.localizedDescription, privacy: .public)")
            handleError(AppError.from(error))
        }
    }

    /// Called after the manager PIN sheet confirms.
    public func submitWithPin(_ pin: String) async {
        managerPin = pin
        showManagerPinPrompt = false
        showFraudWarning = false
        state = .idle
        await submitReturn()
    }

    /// Proceed despite fraud warning (manager PIN gate triggers next).
    public func acknowledgeFraudWarning() {
        showFraudWarning = false
        showManagerPinPrompt = true
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
        case .forbidden:
            state = .failed("You don't have permission to process returns.")
        case .conflict:
            state = .failed("Return amount exceeds what can be refunded for this invoice.")
        case .rateLimited(let seconds):
            if let s = seconds {
                state = .failed("Too many attempts — wait \(s) second\(s == 1 ? "" : "s").")
            } else {
                state = .failed("Too many attempts, please wait.")
            }
        default:
            state = .failed(appError.errorDescription ?? "Return failed. Please try again.")
        }
    }
}
