import Foundation
import Observation
import Networking

// MARK: - Cash Tender State

/// Result of a completed cash tender — passed back to `PosView` so it
/// can build the `PosPostSaleViewModel` with the correct method label and
/// change-due amount.
public struct CashTenderResult: Sendable {
    public let invoiceId: Int64
    public let orderId: String?
    public let totalCents: Int
    public let receivedCents: Int
    public let changeCents: Int

    public var methodLabel: String { "Cash" }
}

/// Phase progression within the cash tender flow.
public enum CashTenderPhase: Sendable, Equatable {
    /// Cashier entering the amount received.
    case entry
    /// Network call in flight.
    case processing
    /// Server returned success — show the change-due card.
    case changeDue(CashTenderResult)
    /// Server returned an error.
    case failed(String)
}

/// ViewModel for `PosCashTenderSheet`. Drives cash-amount entry, change
/// calculation, the `POST /pos/transaction` call, and offline enqueue.
///
/// `@Observable` so the sheet re-renders on every state mutation without
/// manual binding forwarding.
@MainActor
@Observable
public final class CashTenderViewModel {

    // MARK: - Cart snapshot (set by caller at init)

    /// Total the customer owes in cents. Used for change-due arithmetic.
    public let totalCents: Int

    /// Pre-serialised transaction request (immutable after init). The
    /// caller builds this from the Cart just before presenting the sheet.
    public let transactionRequest: PosTransactionRequest

    // MARK: - Mutable state

    /// Raw text the cashier types in the keypad (digits + one decimal point).
    public var rawInput: String = ""

    public var phase: CashTenderPhase = .entry

    // MARK: - Computed from raw input

    /// Parsed dollar amount received. `nil` while the field is empty or
    /// contains an invalid string.
    public var receivedDollars: Double? {
        guard !rawInput.isEmpty else { return nil }
        return Double(rawInput)
    }

    /// Amount received in cents. `nil` while the field is unparseable.
    public var receivedCents: Int? {
        guard let d = receivedDollars else { return nil }
        return Int((d * 100).rounded())
    }

    /// Change due in cents. `0` when cashier enters exact or overpays.
    /// `nil` while the input is empty.
    public var changeCents: Int? {
        guard let rec = receivedCents else { return nil }
        return max(0, rec - totalCents)
    }

    /// Change amount formatted as a currency string.
    public var changeFormatted: String {
        CartMath.formatCents(changeCents ?? 0)
    }

    /// `true` when the input amount is sufficient to cover the total.
    public var canCharge: Bool {
        guard let rec = receivedCents else { return false }
        return rec >= totalCents
    }

    // MARK: - Quick-amount helpers

    /// Populate `rawInput` with the exact amount.
    public func setExact() {
        rawInput = String(format: "%.2f", Double(totalCents) / 100)
    }

    /// Populate `rawInput` rounded up to the nearest `roundTo` dollars.
    public func setRounded(to roundTo: Int) {
        let exact = Double(totalCents) / 100
        let rounded = ceil(exact / Double(roundTo)) * Double(roundTo)
        rawInput = String(format: "%.2f", rounded)
    }

    // MARK: - Input filtering

    /// Accept only digits + one decimal point.
    public func updateInput(_ newValue: String) {
        let filtered = newValue.filter { $0.isNumber || $0 == "." }
        let dotCount = filtered.filter { $0 == "." }.count
        if dotCount <= 1 {
            rawInput = filtered
        }
    }

    // MARK: - Dependencies

    private let api: APIClient?

    // MARK: - Init

    public init(
        totalCents: Int,
        transactionRequest: PosTransactionRequest,
        api: APIClient? = nil
    ) {
        self.totalCents = totalCents
        self.transactionRequest = transactionRequest
        self.api = api
    }

    // MARK: - Charge action

    /// Submit the cash payment to the server.
    ///
    /// Builds the final `PosTransactionRequest` with `paymentMethod: "cash"`
    /// and `paymentAmount` matching `receivedCents`, then posts to
    /// `POST /api/v1/pos/transaction`. On success advances to `.changeDue`.
    public func charge() async {
        guard canCharge, phase == .entry else { return }
        guard let rec = receivedCents else { return }
        guard let api else {
            phase = .failed("No API client configured.")
            return
        }

        phase = .processing

        // Build a new request with the cash-specific fields.
        let cashRequest = PosTransactionRequest(
            items: transactionRequest.items,
            customerId: transactionRequest.customerId,
            discount: transactionRequest.discount,
            tip: transactionRequest.tip,
            notes: transactionRequest.notes,
            paymentMethod: TenderKind.cash.apiValue,
            paymentAmount: Double(rec) / 100,
            payments: nil,
            idempotencyKey: transactionRequest.idempotencyKey
        )

        do {
            let response = try await api.posTransaction(cashRequest)
            let result = CashTenderResult(
                invoiceId: response.invoice.id,
                orderId: response.invoice.orderId,
                totalCents: totalCents,
                receivedCents: rec,
                changeCents: max(0, rec - totalCents)
            )
            phase = .changeDue(result)
        } catch {
            phase = .failed(userFacingMessage(for: error))
        }
    }

    public func resetToEntry() {
        phase = .entry
    }

    // MARK: - Private helpers

    private func userFacingMessage(for error: Error) -> String {
        let desc = error.localizedDescription
        // Strip any ugly `APITransportError` prefix so the cashier sees
        // a clean message.
        if desc.contains("httpStatus") {
            return "The server rejected the transaction. Please check the cart and try again."
        }
        if desc.contains("cancelled") || desc.contains("URLError") {
            return "Network request timed out. Check your connection and retry."
        }
        return desc
    }
}
