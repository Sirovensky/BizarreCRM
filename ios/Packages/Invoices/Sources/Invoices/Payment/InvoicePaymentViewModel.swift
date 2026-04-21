import Foundation
import Observation
import Core
import DesignSystem
import Networking

// §7.3 Invoice Payment ViewModel — POST /api/v1/invoices/:id/payment

public enum InvoiceTender: String, CaseIterable, Sendable, Identifiable {
    case cash        = "cash"
    case card        = "card"
    case giftCard    = "gift_card"
    case storeCredit = "store_credit"
    case check       = "check"
    case other       = "other"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cash:        return "Cash"
        case .card:        return "Card"
        case .giftCard:    return "Gift Card"
        case .storeCredit: return "Store Credit"
        case .check:       return "Check"
        case .other:       return "Other"
        }
    }
}

public struct RecordPaymentRequest: Encodable, Sendable {
    public let tender: String
    public let amountCents: Int
    public let feeCents: Int?
    public let notes: String?
    public let idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case tender
        case amountCents   = "amount_cents"
        case feeCents      = "fee_cents"
        case notes
        case idempotencyKey = "idempotency_key"
    }
}

public struct PaymentResult: Decodable, Sendable {
    public let id: Int64
    public let status: String?
    public let amountCents: Int?
    public let balanceCents: Int?

    enum CodingKeys: String, CodingKey {
        case id, status
        case amountCents  = "amount_cents"
        case balanceCents = "balance_cents"
    }
}

@MainActor
@Observable
public final class InvoicePaymentViewModel {

    // MARK: - Form fields

    public var tender: InvoiceTender = .cash
    /// Amount entered by user, in cents. Defaults to balance due.
    public var amountCents: Int
    public var feeCents: Int = 0
    public var notes: String = ""

    // MARK: - Validation

    public var amountString: String = "" {
        didSet {
            if let dollars = Double(amountString.filter { $0.isNumber || $0 == "." }) {
                amountCents = Int((dollars * 100).rounded())
            }
        }
    }

    // MARK: - State

    public enum State: Sendable {
        case idle
        case submitting
        case success(PaymentResult)
        case failed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var fieldErrors: [String: String] = [:]

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient
    public let invoiceId: Int64
    public let balanceCents: Int

    public init(api: APIClient, invoiceId: Int64, balanceCents: Int) {
        self.api = api
        self.invoiceId = invoiceId
        self.balanceCents = balanceCents
        self.amountCents = balanceCents
        let dollars = String(format: "%.2f", Double(balanceCents) / 100.0)
        self.amountString = dollars
    }

    // MARK: - Validation

    public var isValid: Bool {
        amountCents > 0
    }

    public var isPartialPayment: Bool {
        amountCents < balanceCents && amountCents > 0
    }

    // MARK: - Submit

    public func applyPayment() async {
        guard isValid else {
            state = .failed("Enter a valid amount.")
            return
        }
        guard case .idle = state else { return }
        state = .submitting
        fieldErrors = [:]

        let body = RecordPaymentRequest(
            tender: tender.rawValue,
            amountCents: amountCents,
            feeCents: feeCents > 0 ? feeCents : nil,
            notes: notes.isEmpty ? nil : notes,
            idempotencyKey: UUID().uuidString
        )

        do {
            let result = try await api.post(
                "/api/v1/invoices/\(invoiceId)/payment",
                body: body,
                as: PaymentResult.self
            )
            state = .success(result)
            BrandHaptics.success()
        } catch {
            AppLog.ui.error("Payment failed: \(error.localizedDescription, privacy: .public)")
            handleError(AppError.from(error))
        }
    }

    // MARK: - Error mapping

    private func handleError(_ appError: AppError) {
        switch appError {
        case .validation(let errors):
            fieldErrors = errors
            state = .failed(errors.values.first ?? appError.errorDescription ?? "Validation error.")
        case .conflict:
            state = .failed("Invoice already paid.")
        case .rateLimited(let seconds):
            if let s = seconds {
                state = .failed("Too many attempts, wait \(s) second\(s == 1 ? "" : "s").")
            } else {
                state = .failed("Too many attempts, please wait.")
            }
        default:
            state = .failed(appError.errorDescription ?? "Payment failed.")
        }
    }

    public func resetToIdle() {
        if case .failed = state { state = .idle }
    }
}
