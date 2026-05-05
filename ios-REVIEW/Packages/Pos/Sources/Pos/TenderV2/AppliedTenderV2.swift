import Foundation
import Networking

/// §D — A tender leg that has been committed during the v2 two-step tender flow.
///
/// This is a separate type from the v1 `AppliedTender` (which covers gift-card
/// and store-credit pre-applies). `AppliedTenderV2` represents a payment
/// method + amount the cashier has confirmed in the new picker → entry flow.
///
/// `reference` carries any method-specific token (gift card code suffix,
/// store-credit transaction id, card auth-code) for receipt display.
public struct AppliedTenderV2: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    /// The tender method used for this leg.
    public let method: TenderMethod
    /// Amount applied in cents. Always > 0.
    public let amountCents: Int
    /// Optional method-specific reference for receipt reconciliation.
    /// e.g. gift card "••••4C7A", card "Auth: A12345".
    public let reference: String?

    public init(
        id: UUID = UUID(),
        method: TenderMethod,
        amountCents: Int,
        reference: String? = nil
    ) {
        self.id = id
        self.method = method
        self.amountCents = max(0, amountCents)
        self.reference = reference
    }
}

public extension AppliedTenderV2 {
    /// Convert to a `PosPaymentLeg` for `POST /api/v1/pos/transaction`.
    func toPaymentLeg() -> PosPaymentLeg {
        PosPaymentLeg(
            method: method.apiValue,
            amount: Double(amountCents) / 100.0,
            reference: reference
        )
    }
}
