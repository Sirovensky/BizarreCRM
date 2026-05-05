import Foundation
import Observation
import Networking
import Core

/// §D — Stage the tender two-step UI is in.
public enum TenderStage: Sendable, Equatable {
    /// Step 1 — cashier is selecting a payment method.
    case method
    /// Step 2 — cashier is entering the amount for the chosen method.
    case amount
    /// All tender legs cover the total; transaction confirmed.
    case confirmed
}

/// §D — Result payload delivered to the parent when `stage == .confirmed`.
public struct TenderConfirmResult: Sendable, Equatable {
    public let invoiceId: Int64
    public let orderId: String?
    public let totalCents: Int
    public let tenders: [AppliedTenderV2]
    public let changeCents: Int

    public init(
        invoiceId: Int64,
        orderId: String?,
        totalCents: Int,
        tenders: [AppliedTenderV2],
        changeCents: Int
    ) {
        self.invoiceId = invoiceId
        self.orderId = orderId
        self.totalCents = totalCents
        self.tenders = tenders
        self.changeCents = changeCents
    }
}

/// §D — Coordinator for the v2 two-step tender UI.
///
/// State machine:
/// ```
///   .method → .amount → .confirmed (full payment)
///   .method → .amount → .method    (partial — remaining balance)
/// ```
///
/// On partial payment the coordinator records the applied tender,
/// reduces `remaining`, resets `method` to nil, and returns to `.method`
/// so the cashier can add another leg.
///
/// Calling `confirm()` posts `POST /api/v1/pos/transaction` with the
/// accumulated `payments` array and transitions to `.confirmed`.
///
/// NOTE — Server route reconciliation:
/// The spec mentioned `POST /transactions/:id/split` and `/:id/void` routes
/// which do NOT exist on the server. The server models split tenders via the
/// `payments: [...]` array on `POST /api/v1/pos/transaction` (single atomic
/// call). The coordinator accumulates all legs client-side and submits once.
/// For void/mistake recovery use the existing `POST /api/v1/pos/return`.
///
/// The coordinator does NOT push navigation itself — it is observed by
/// `PosTenderMethodPickerView` / `PosTenderAmountEntryView` which read
/// `stage` and render accordingly.
@MainActor
@Observable
public final class PosTenderCoordinator {

    // MARK: - Public state

    /// Currently selected method (nil between legs).
    public private(set) var method: TenderMethod?

    /// Tender legs already applied this session.
    public private(set) var appliedTenders: [AppliedTenderV2] = []

    /// Remaining balance in cents (original total minus applied legs).
    public private(set) var remaining: Int

    /// True once the cashier has applied more than one leg.
    public var isSplit: Bool { appliedTenders.count >= 1 && remaining > 0 }

    /// Current stage of the two-step flow.
    public private(set) var stage: TenderStage = .method

    /// Tip in cents (added by cashier in `PosTenderAmountBar`).
    public private(set) var tipCents: Int = 0

    /// Error message surfaced by the last `confirm()` call, if any.
    public private(set) var errorMessage: String?

    /// True while `confirm()` is awaiting the server.
    public private(set) var isConfirming: Bool = false

    /// Set after a successful `confirm()`.
    public private(set) var confirmResult: TenderConfirmResult?

    // MARK: - Private

    /// Original cart total (cents) — immutable after init.
    public let totalCents: Int

    /// Pre-built transaction request (items, customer, discount).
    /// Payments array is overridden at confirm time.
    private let baseRequest: PosTransactionRequest

    @ObservationIgnored private let api: APIClient

    // MARK: - Init

    public init(
        totalCents: Int,
        baseRequest: PosTransactionRequest,
        api: APIClient
    ) {
        self.totalCents = totalCents
        self.remaining = totalCents
        self.baseRequest = baseRequest
        self.api = api
    }

    // MARK: - Navigation

    /// Cashier tapped a method tile — advance to amount entry.
    public func selectMethod(_ m: TenderMethod) {
        method = m
        stage = .amount
        errorMessage = nil
    }

    /// Cancel the current amount-entry step; return to method picker.
    public func cancelAmountEntry() {
        method = nil
        stage = .method
    }

    /// Apply a partial or full tender leg.
    ///
    /// - Parameters:
    ///   - amountCents: How much this leg covers (must be > 0 and ≤ remaining
    ///     after the first leg, or equal to remaining for full payment).
    ///   - reference: Optional method-specific reference token.
    ///
    /// If `amountCents == remaining`, the flow advances to `.confirmed`.
    /// Otherwise `remaining` is reduced and stage returns to `.method`.
    public func applyTender(amountCents: Int, reference: String? = nil) {
        guard let m = method, amountCents > 0 else { return }

        let clamped = min(amountCents, remaining)
        let leg = AppliedTenderV2(method: m, amountCents: clamped, reference: reference)
        appliedTenders.append(leg)
        remaining -= clamped

        if remaining <= 0 {
            remaining = 0
            // All paid — ready to confirm. The actual network call is
            // triggered by `PosTenderAmountBar` via `confirm()`.
        } else {
            // Partial — go back to method picker for the next leg.
            method = nil
            stage = .method
        }
    }

    /// Add a tip (called from `PosTenderAmountBar`). Tip is not deducted
    /// from `remaining`; it is passed to the server as a separate field.
    public func setTip(cents: Int) {
        tipCents = max(0, cents)
    }

    /// Remove the most recently applied tender leg (undo).
    public func removeLastTender() {
        guard let last = appliedTenders.last else { return }
        appliedTenders.removeLast()
        remaining += last.amountCents
        if stage == .confirmed { stage = .method }
        method = nil
        stage = .method
    }

    /// Dismiss the current error message (called by the error alert's OK action).
    public func clearError() {
        errorMessage = nil
    }

    /// Reset the entire flow back to step 1.
    public func reset() {
        method = nil
        appliedTenders = []
        remaining = totalCents
        tipCents = 0
        stage = .method
        errorMessage = nil
        confirmResult = nil
        isConfirming = false
    }

    // MARK: - Confirm

    /// POST the transaction to the server.
    ///
    /// Should be called when `remaining == 0` (all legs applied).
    /// Transitions: `isConfirming = true` → `.confirmed` / error.
    public func confirm() async {
        guard remaining == 0, !appliedTenders.isEmpty else { return }
        guard !isConfirming else { return }

        isConfirming = true
        errorMessage = nil

        let tipDollars: Double? = tipCents > 0 ? Double(tipCents) / 100.0 : nil
        let legs = appliedTenders.map { $0.toPaymentLeg() }

        let request: PosTransactionRequest
        if legs.count == 1 {
            // Single-payment path
            let leg = legs[0]
            request = PosTransactionRequest(
                items: baseRequest.items,
                customerId: baseRequest.customerId,
                discount: baseRequest.discount,
                tip: tipDollars,
                notes: baseRequest.notes,
                paymentMethod: leg.method,
                paymentAmount: leg.amount,
                idempotencyKey: baseRequest.idempotencyKey
            )
        } else {
            // Split-payment path
            request = PosTransactionRequest(
                items: baseRequest.items,
                customerId: baseRequest.customerId,
                discount: baseRequest.discount,
                tip: tipDollars,
                notes: baseRequest.notes,
                paymentMethod: nil,
                paymentAmount: nil,
                payments: legs,
                idempotencyKey: baseRequest.idempotencyKey
            )
        }

        do {
            let response = try await api.posTransaction(request)
            let serverTotal: Int
            if let tc = response.invoice.totalCents {
                serverTotal = tc
            } else if let t = response.invoice.total {
                serverTotal = Int((t * 100).rounded())
            } else {
                serverTotal = totalCents
            }

            let paidTotal = appliedTenders.reduce(0) { $0 + $1.amountCents }
            let changeCents = max(0, paidTotal - serverTotal)

            confirmResult = TenderConfirmResult(
                invoiceId: response.invoice.id,
                orderId: response.invoice.orderId,
                totalCents: serverTotal,
                tenders: appliedTenders,
                changeCents: changeCents
            )
            stage = .confirmed

        } catch {
            AppLog.pos.error("PosTenderCoordinator confirm failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }

        isConfirming = false
    }
}
