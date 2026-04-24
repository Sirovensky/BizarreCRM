#if canImport(UIKit)
import Foundation
import Observation
import Networking

// MARK: - GiftCardRedeemViewModel

/// §40 — State machine for `GiftCardRedeemSheet`.
///
/// Applies a gift card as a tender at POS via
/// `POST /api/v1/gift-cards/:id/redeem`.
///
/// The server enforces the atomic decrement and expiry re-check; this VM is
/// a thin shell. The only local validation is that `amountCents` must be
/// positive and must not exceed the card's current balance (fast-fail to
/// save a round trip — the server also enforces this).
///
/// State machine:
///   `.idle` → `.redeeming` → `.redeemed(remainingBalanceCents:)`
///   `.idle` → `.redeeming` → `.failure(String)`
///
/// Money in cents. `RedeemGiftCardRequest` converts cents → dollars at the
/// wire boundary.
@MainActor
@Observable
public final class GiftCardRedeemViewModel {

    // MARK: - State

    public enum State: Equatable, Sendable {
        case idle
        case redeeming
        case redeemed(remainingBalanceCents: Int)
        case failure(String)
    }

    // MARK: - Properties

    public private(set) var state: State = .idle

    /// Card to redeem against. Set by the caller before presenting the sheet.
    public var card: GiftCard?

    /// Cents to redeem — cashier enters as integer string.
    public var amountInput: String = ""

    /// Optional reason / reference for the transaction log.
    public var reason: String = ""

    /// Optional invoice id to link the redemption.
    public var invoiceId: Int64?

    private let api: APIClient

    // MARK: - Init

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Computed

    public var amountCents: Int {
        Int(amountInput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// User-facing validation error or `nil` when the form is valid.
    public var validationError: String? {
        guard let card else { return "No card selected." }
        guard card.active else { return "Card is not active." }
        guard amountCents > 0 else { return "Enter an amount greater than zero." }
        if amountCents > card.balanceCents {
            return "Amount exceeds card balance (\(CartMath.formatCents(card.balanceCents)))."
        }
        return nil
    }

    public var canRedeem: Bool {
        validationError == nil && state != .redeeming
    }

    /// Remaining balance preview shown while the cashier types.
    public var previewRemainingCents: Int? {
        guard let card, validationError == nil else { return nil }
        return card.balanceCents - amountCents
    }

    // MARK: - Actions

    /// `POST /api/v1/gift-cards/:id/redeem`
    public func redeem() async {
        guard let card, canRedeem else { return }
        state = .redeeming
        let reasonTrimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let response = try await api.redeemGiftCard(
                id: card.id,
                amountCents: amountCents,
                reason: reasonTrimmed.isEmpty ? nil : reasonTrimmed
            )
            state = .redeemed(remainingBalanceCents: response.remainingBalanceCents)
        } catch let APITransportError.httpStatus(code, message) {
            let msg = (message?.isEmpty == false) ? message! : "Redeem failed"
            state = .failure("Redeem failed (\(code)): \(msg)")
        } catch {
            state = .failure("Redeem failed: \(error.localizedDescription)")
        }
    }

    public func reset() {
        state = .idle
        amountInput = ""
        reason = ""
        invoiceId = nil
    }
}
#endif
