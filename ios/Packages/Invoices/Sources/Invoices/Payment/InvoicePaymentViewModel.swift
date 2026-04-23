import Foundation
import Observation
import Core
import DesignSystem
import Networking

// §7.3 / §7.4 Invoice Payment ViewModel
// Endpoint: POST /api/v1/invoices/:id/payments
// Server fields: amount (Double dollars), method, method_detail, transaction_id, notes, payment_type

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

    /// Whether this method requires a reference/transaction ID field.
    public var needsReference: Bool {
        switch self {
        case .card, .check, .giftCard: return true
        default: return false
        }
    }
}

/// One leg of a split-tender payment.
public struct PaymentLeg: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var tender: InvoiceTender
    public var amountCents: Int
    public var reference: String

    public init(id: UUID = UUID(), tender: InvoiceTender = .cash, amountCents: Int = 0, reference: String = "") {
        self.id = id
        self.tender = tender
        self.amountCents = amountCents
        self.reference = reference
    }
}

/// Result returned to the caller after a successful payment.
/// Mirrors `RecordPaymentResponse` from Networking but lives in the Invoices module
/// so callers don't need to import Networking directly.
public struct PaymentResult: Sendable, Equatable {
    public let id: Int64
    public let status: String?
    public let amountPaid: Double?
    public let amountDue: Double?

    public init(id: Int64, status: String?, amountPaid: Double?, amountDue: Double?) {
        self.id = id
        self.status = status
        self.amountPaid = amountPaid
        self.amountDue = amountDue
    }

    init(from response: RecordPaymentResponse) {
        self.id = response.id
        self.status = response.status
        self.amountPaid = response.amountPaid
        self.amountDue = response.amountDue
    }
}

@MainActor
@Observable
public final class InvoicePaymentViewModel {

    // MARK: - Form fields

    /// Split-tender legs. At minimum one leg.
    public private(set) var legs: [PaymentLeg]
    public var notes: String = ""

    // MARK: - State

    public enum State: Sendable, Equatable {
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
    /// Customer ID required by server for validation when provided.
    public let customerId: Int64?

    public init(api: APIClient, invoiceId: Int64, balanceCents: Int, customerId: Int64? = nil) {
        self.api = api
        self.invoiceId = invoiceId
        self.balanceCents = balanceCents
        self.customerId = customerId
        // Start with a single cash leg covering the full balance.
        self.legs = [PaymentLeg(tender: .cash, amountCents: balanceCents)]
    }

    // MARK: - Single-leg convenience (backward compat with existing UI)

    /// Primary tender — mirrors the first leg.
    public var tender: InvoiceTender {
        get { legs.first?.tender ?? .cash }
        set {
            guard !legs.isEmpty else { return }
            legs[0] = PaymentLeg(id: legs[0].id, tender: newValue, amountCents: legs[0].amountCents, reference: legs[0].reference)
        }
    }

    /// Amount in cents for the first leg.
    public var amountCents: Int {
        get { legs.first?.amountCents ?? 0 }
        set {
            guard !legs.isEmpty else { return }
            legs[0] = PaymentLeg(id: legs[0].id, tender: legs[0].tender, amountCents: newValue, reference: legs[0].reference)
        }
    }

    public var amountString: String = "" {
        didSet {
            if let dollars = Double(amountString.filter { $0.isNumber || $0 == "." }) {
                amountCents = Int((dollars * 100).rounded())
            }
        }
    }

    /// Total cents across all legs.
    public var totalTenderedCents: Int {
        legs.reduce(0) { $0 + $1.amountCents }
    }

    /// Remaining unallocated balance (can be negative for overpayment).
    public var remainingCents: Int {
        balanceCents - totalTenderedCents
    }

    public var isPartialPayment: Bool {
        totalTenderedCents < balanceCents && totalTenderedCents > 0
    }

    public var isOverpayment: Bool {
        totalTenderedCents > balanceCents
    }

    /// Change due for cash tender when overpaid.
    public var changeDueCents: Int {
        max(0, totalTenderedCents - balanceCents)
    }

    // MARK: - Validation

    public var isValid: Bool {
        totalTenderedCents > 0 && legs.allSatisfy { $0.amountCents > 0 }
    }

    // MARK: - Split tender management

    public func addLeg() {
        let rem = max(0, remainingCents)
        legs.append(PaymentLeg(tender: .card, amountCents: rem))
    }

    public func removeLeg(at offsets: IndexSet) {
        guard legs.count > 1 else { return }
        legs.remove(atOffsets: offsets)
    }

    public func updateLeg(id: UUID, tender: InvoiceTender? = nil, amountCents: Int? = nil, reference: String? = nil) {
        guard let idx = legs.firstIndex(where: { $0.id == id }) else { return }
        let old = legs[idx]
        legs[idx] = PaymentLeg(
            id: old.id,
            tender: tender ?? old.tender,
            amountCents: amountCents ?? old.amountCents,
            reference: reference ?? old.reference
        )
    }

    // MARK: - Submit

    /// Submit all legs sequentially. Succeeds when all post successfully.
    /// On partial failure: state = .failed, but already-posted legs remain on the server.
    public func applyPayment() async {
        guard isValid else {
            state = .failed("Enter a valid amount.")
            return
        }
        guard case .idle = state else { return }
        state = .submitting
        fieldErrors = [:]

        var lastResponse: RecordPaymentResponse?
        for leg in legs {
            let dollars = Double(leg.amountCents) / 100.0
            let body = RecordInvoicePaymentRequest(
                amount: dollars,
                method: leg.tender.rawValue,
                methodDetail: leg.reference.isEmpty ? nil : leg.reference,
                transactionId: nil,
                notes: notes.isEmpty ? nil : notes,
                paymentType: "payment"
            )
            do {
                lastResponse = try await api.recordPayment(invoiceId: invoiceId, body: body)
            } catch {
                AppLog.ui.error("Payment leg failed: \(error.localizedDescription, privacy: .public)")
                handleError(AppError.from(error))
                return
            }
        }

        if let response = lastResponse {
            state = .success(PaymentResult(from: response))
            BrandHaptics.success()
        } else {
            state = .failed("No payment recorded.")
        }
    }

    // MARK: - Error mapping

    private func handleError(_ appError: AppError) {
        switch appError {
        case .validation(let errors):
            fieldErrors = errors
            state = .failed(errors.values.first ?? appError.errorDescription ?? "Validation error.")
        case .conflict:
            state = .failed("Duplicate payment detected. Please wait before retrying.")
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
