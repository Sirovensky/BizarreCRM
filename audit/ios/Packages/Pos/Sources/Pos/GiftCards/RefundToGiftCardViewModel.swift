#if canImport(UIKit)
import Foundation
import Observation
import Networking

// MARK: - RefundToGiftCardViewModel

/// State for `RefundToGiftCardSheet`.
///
/// On invoice refund the cashier can choose to put the money back to:
/// a) the original tender (card/cash) — `toGiftCard = false`
/// b) a new gift card — `toGiftCard = true`
///
/// POST /invoices/:id/refund body: `{ amount, toGiftCard, reason? }`
@MainActor
@Observable
public final class RefundToGiftCardViewModel {

    // MARK: - State

    public enum State: Equatable, Sendable {
        case idle
        case processing
        case success(InvoiceRefundResponse)
        case failure(String)
    }

    // MARK: - Properties

    public private(set) var state: State = .idle

    public let invoiceId: Int64
    /// Refund amount in cents (pre-set from the calling invoice refund flow).
    public var amountCents: Int
    /// When `true`, server issues a new gift card for `amountCents`.
    public var toGiftCard: Bool = false
    /// Optional reason — required by some tenant policies.
    public var reason: String = ""

    private let api: APIClient

    // MARK: - Init

    public init(invoiceId: Int64, amountCents: Int, api: APIClient) {
        self.invoiceId = invoiceId
        self.amountCents = amountCents
        self.api = api
    }

    // MARK: - Computed

    public var canRefund: Bool {
        amountCents > 0 && state != .processing
    }

    // MARK: - Actions

    public func submitRefund() async {
        guard canRefund else { return }
        state = .processing
        let request = InvoiceRefundRequest(
            amountCents: amountCents,
            toGiftCard: toGiftCard,
            reason: reason.isEmpty ? nil : reason
        )
        do {
            let response = try await api.refundInvoice(id: invoiceId, request: request)
            state = .success(response)
        } catch let APITransportError.httpStatus(code, message) {
            let msg = (message?.isEmpty == false) ? message! : "Refund failed"
            state = .failure("Refund failed (\(code)): \(msg)")
        } catch {
            state = .failure("Refund failed: \(error.localizedDescription)")
        }
    }

    public func reset() {
        state = .idle
        toGiftCard = false
        reason = ""
    }
}
#endif
