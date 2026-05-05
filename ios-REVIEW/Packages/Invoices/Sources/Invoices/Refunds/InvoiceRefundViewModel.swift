import Foundation
import Observation
import Core
import Networking

// §7.4 Invoice Refund ViewModel
// Endpoint: POST /api/v1/refunds (not /invoices/:id/refund — verified against refunds.routes.ts)
// Server body: { invoice_id, customer_id, amount (dollars), type, reason, method }
// Server response: { success: true, data: { id } }
// Two-step: create (pending) → approve (admin PATCH /refunds/:id/approve)

public enum RefundReason: String, CaseIterable, Sendable, Identifiable {
    case returnItem    = "return"
    case priceDispute  = "price_dispute"
    case goodwill      = "goodwill"
    case other         = "other"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .returnItem:   return "Return"
        case .priceDispute: return "Price Dispute"
        case .goodwill:     return "Goodwill"
        case .other:        return "Other"
        }
    }
}

public enum RefundType: String, CaseIterable, Sendable, Identifiable {
    case refund      = "refund"
    case storeCredit = "store_credit"
    case creditNote  = "credit_note"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .refund:      return "Refund"
        case .storeCredit: return "Store Credit"
        case .creditNote:  return "Credit Note"
        }
    }
}

public struct RefundLineItem: Sendable, Identifiable, Hashable {
    public let id: Int64
    public let displayName: String
    public let totalCents: Int
    public var isSelected: Bool
    public var refundCents: Int

    public init(id: Int64, displayName: String, totalCents: Int, isSelected: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.totalCents = totalCents
        self.isSelected = isSelected
        self.refundCents = totalCents
    }
}

public struct RefundResult: Decodable, Sendable, Equatable {
    public let id: Int64

    enum CodingKeys: String, CodingKey {
        case id
    }
}

/// Manager PIN is required when refund > $100 (10_000 cents).
public let kRefundManagerPinThresholdCents: Int = 10_000

@MainActor
@Observable
public final class InvoiceRefundViewModel {

    // MARK: - Form fields

    public var reason: RefundReason = .returnItem
    public var refundType: RefundType = .refund
    public var refundMethod: InvoiceTender = .card
    public var lineItems: [RefundLineItem]
    public var useLineItems: Bool = false
    public var manualAmountCents: Int
    public var manualAmountString: String = "" {
        didSet {
            if let dollars = Double(manualAmountString.filter { $0.isNumber || $0 == "." }) {
                manualAmountCents = Int((dollars * 100).rounded())
            }
        }
    }
    public var managerPin: String = ""
    public var showManagerPinPrompt: Bool = false

    // MARK: - State

    public enum State: Sendable, Equatable {
        case idle
        case submitting
        case success(RefundResult)
        case failed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var fieldErrors: [String: String] = [:]

    @ObservationIgnored private let api: APIClient
    public let invoiceId: Int64
    public let customerId: Int64
    public let totalPaidCents: Int

    public init(
        api: APIClient,
        invoiceId: Int64,
        customerId: Int64,
        totalPaidCents: Int,
        lineItems: [RefundLineItem] = []
    ) {
        self.api = api
        self.invoiceId = invoiceId
        self.customerId = customerId
        self.totalPaidCents = totalPaidCents
        self.lineItems = lineItems
        self.manualAmountCents = totalPaidCents
        self.manualAmountString = String(format: "%.2f", Double(totalPaidCents) / 100.0)
    }

    // MARK: - Computed

    public var effectiveAmountCents: Int {
        if useLineItems {
            return lineItems.filter(\.isSelected).reduce(0) { $0 + $1.refundCents }
        }
        return manualAmountCents
    }

    public var requiresManagerPin: Bool {
        effectiveAmountCents > kRefundManagerPinThresholdCents
    }

    public var isValid: Bool {
        effectiveAmountCents > 0 && effectiveAmountCents <= totalPaidCents
    }

    // MARK: - Submit

    public func submitRefund() async {
        guard isValid else {
            state = .failed("Enter a valid refund amount.")
            return
        }
        if requiresManagerPin && managerPin.isEmpty {
            showManagerPinPrompt = true
            return
        }
        guard case .idle = state else { return }
        state = .submitting
        fieldErrors = [:]

        let dollars = Double(effectiveAmountCents) / 100.0
        let body = CreateRefundRequest(
            invoiceId: invoiceId,
            customerId: customerId,
            amount: dollars,
            type: refundType.rawValue,
            reason: reason.rawValue,
            method: refundMethod.rawValue
        )

        do {
            let result = try await api.createRefund(body: body)
            state = .success(RefundResult(id: result.id))
        } catch {
            AppLog.ui.error("Refund failed: \(error.localizedDescription, privacy: .public)")
            handleError(AppError.from(error))
        }
    }

    public func submitWithPin(_ pin: String) async {
        managerPin = pin
        showManagerPinPrompt = false
        state = .idle
        await submitRefund()
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
            state = .failed("You don't have permission to issue refunds.")
        case .conflict:
            state = .failed("Refund amount exceeds amount paid or available balance.")
        case .rateLimited(let seconds):
            if let s = seconds {
                state = .failed("Too many attempts, wait \(s) second\(s == 1 ? "" : "s").")
            } else {
                state = .failed("Too many attempts, please wait.")
            }
        default:
            state = .failed(appError.errorDescription ?? "Refund failed.")
        }
    }
}
