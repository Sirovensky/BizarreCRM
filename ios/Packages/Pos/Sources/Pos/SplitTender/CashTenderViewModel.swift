#if canImport(UIKit)
import Foundation
import Observation
import Networking
import DesignSystem

/// Result of a successful cash transaction.
public struct CashTenderResult: Sendable, Equatable {
    public let invoiceId: Int64
    public let orderId: String?
    public let totalCents: Int
    /// Amount given by the customer (may exceed total).
    public let receivedCents: Int
    /// Change due back to the customer (`receivedCents - totalCents`).
    public let changeCents: Int

    public var methodLabel: String { "Cash" }

    public init(
        invoiceId: Int64,
        orderId: String?,
        totalCents: Int,
        receivedCents: Int,
        changeCents: Int
    ) {
        self.invoiceId = invoiceId
        self.orderId = orderId
        self.totalCents = totalCents
        self.receivedCents = receivedCents
        self.changeCents = changeCents
    }
}

/// State machine for the cash tender sheet.
public enum CashTenderPhase: Sendable, Equatable {
    /// Cashier is entering the amount received.
    case entry
    /// Waiting for the server response.
    case processing
    /// Transaction complete — show the change-due card.
    case changeDue(CashTenderResult)
    /// Network or server error — user can retry.
    case failed(String)
}

/// §16.5 — View model for the cash tender sheet. Handles:
/// - Input validation (digits + optional decimal).
/// - Quick-amount helpers (exact, rounded $5/$10/$20/$50/$100).
/// - Posting to `/pos/transaction` and transitioning through phases.
@MainActor
@Observable
public final class CashTenderViewModel: Identifiable {
    /// Stable identity for `.sheet(item:)` presentation.
    public let id: UUID = UUID()
    public let totalCents: Int
    public let transactionRequest: PosTransactionRequest

    public var rawInput: String = ""
    public var phase: CashTenderPhase = .entry

    @ObservationIgnored private let api: APIClient

    /// Computed: amount entered as cents. 0 when input is empty or invalid.
    public var receivedCents: Int {
        let cleaned = rawInput.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "$", with: "")
        guard !cleaned.isEmpty, let dollars = Double(cleaned) else { return 0 }
        return Int((dollars * 100).rounded())
    }

    /// Change to return, clamped to ≥ 0.
    public var changeCents: Int {
        max(0, receivedCents - totalCents)
    }

    /// Formatted change string for live preview.
    public var changeFormatted: String {
        CartMath.formatCents(changeCents)
    }

    /// Charge button is enabled when received ≥ total and phase is .entry.
    public var canCharge: Bool {
        phase == .entry && receivedCents >= totalCents
    }

    public init(totalCents: Int, transactionRequest: PosTransactionRequest, api: APIClient) {
        self.totalCents = totalCents
        self.transactionRequest = transactionRequest
        self.api = api
    }

    /// Sets the input to the exact total due.
    public func setExact() {
        let dollars = Double(totalCents) / 100.0
        rawInput = String(format: "%.2f", dollars)
    }

    /// Sets input to the next multiple of `roundTo` cents (e.g. 500 = $5).
    public func setRounded(to roundTo: Int) {
        guard roundTo > 0 else { return }
        let rounded = ((totalCents + roundTo - 1) / roundTo) * roundTo
        let dollars = Double(rounded) / 100.0
        rawInput = String(format: "%.2f", dollars)
    }

    /// Filters the raw input to digits and at most one decimal point.
    public func updateInput(_ newValue: String) {
        let stripped = newValue.replacingOccurrences(of: "$", with: "")
        var dotSeen = false
        let filtered = stripped.unicodeScalars.filter { scalar in
            if scalar == "." {
                if dotSeen { return false }
                dotSeen = true
                return true
            }
            return CharacterSet.decimalDigits.contains(scalar)
        }
        rawInput = String(String.UnicodeScalarView(filtered))
    }

    /// POST the transaction. Transitions .entry → .processing → .changeDue / .failed.
    public func charge() async {
        guard canCharge else { return }
        phase = .processing

        // Rebuild request with the actual amount received (not the total).
        let received = receivedCents
        let paidDollars = Double(received) / 100.0
        let finalRequest = PosTransactionRequest(
            items: transactionRequest.items,
            customerId: transactionRequest.customerId,
            discount: transactionRequest.discount,
            tip: transactionRequest.tip,
            notes: transactionRequest.notes,
            paymentMethod: TenderKind.cash.apiValue,
            paymentAmount: paidDollars,
            payments: transactionRequest.payments,
            idempotencyKey: transactionRequest.idempotencyKey
        )

        do {
            let response = try await api.posTransaction(finalRequest)
            let serverTotal: Int
            if let tc = response.invoice.totalCents {
                serverTotal = tc
            } else if let t = response.invoice.total {
                serverTotal = Int((t * 100).rounded())
            } else {
                serverTotal = totalCents
            }
            let result = CashTenderResult(
                invoiceId: response.invoice.id,
                orderId: response.invoice.orderId,
                totalCents: serverTotal,
                receivedCents: received,
                changeCents: max(0, received - serverTotal)
            )
            phase = .changeDue(result)
            BrandHaptics.success()
        } catch {
            phase = .failed(error.localizedDescription)
            BrandHaptics.error()
        }
    }

    /// Return to entry phase for retry after a failure.
    public func resetToEntry() {
        phase = .entry
    }
}
#endif
