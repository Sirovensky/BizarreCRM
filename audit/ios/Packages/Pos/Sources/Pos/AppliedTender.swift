import Foundation

/// §40 — A tender already applied to the cart prior to swiping a card.
/// Gift cards + customer store credit are the two kinds shipped in this
/// phase; the `Kind` enum is deliberately open (store-value only) so the
/// UI layer never mixes a tender row with a payment-rail row. Cash, card,
/// and payment-link totals land in `CartPayment` (§16.5), not here.
///
/// `id` is minted client-side so the cart can optimistically render the
/// row before the server round-trip (redeem POST) completes — the server
/// has no equivalent identifier for the client-side row.
///
/// `reference` carries the server-side anchor so the receipt renderer can
/// surface the last 4 digits of a gift card code, the customer id behind a
/// store-credit row, or any other human-readable tag for reconciliation.
public struct AppliedTender: Identifiable, Equatable, Hashable, Sendable {

    /// Which tender rail produced this row. `label` + `reference` carry
    /// the display data, so the enum stays tiny — adding a new rail
    /// (loyalty, in-store deposit) only means a new case here + wiring in
    /// the sheet that creates it.
    public enum Kind: String, Sendable, Equatable, Hashable {
        case giftCard
        case storeCredit
        /// Loyalty-points redemption. Points are exchanged for a dollar-off
        /// credit at checkout; the server converts points → cents server-side.
        case loyaltyRedemption

        // MARK: - §16 Payment method icon SF Symbols

        /// SF Symbol representing this tender kind in cart totals rows,
        /// receipts, and the applied-tender chip in `PosCartPanel`.
        ///
        /// Symbols are all "fill" weight to match the `TenderMethod.systemImage`
        /// conventions used on the method-picker tiles.
        public var systemImage: String {
            switch self {
            case .giftCard:         return "giftcard.fill"
            case .storeCredit:      return "dollarsign.circle.fill"
            case .loyaltyRedemption: return "star.circle.fill"
            }
        }

        /// Accessible label used when the icon is the only visual indicator.
        public var accessibilityLabel: String {
            switch self {
            case .giftCard:          return "Gift card"
            case .storeCredit:       return "Store credit"
            case .loyaltyRedemption: return "Loyalty points"
            }
        }
    }

    public let id: UUID
    public let kind: Kind
    /// Amount in cents. Always positive — the Cart clamps on apply so a
    /// negative row can't sneak onto the list. A full-drain row equals the
    /// full remaining balance of the source.
    public let amountCents: Int
    /// Human-readable label shown in the totals footer. e.g.
    /// "Gift card ••••4C7A" or "Store credit".
    public let label: String
    /// Optional backend identifier (gift card id, customer id, transaction
    /// id) used by the receipt renderer + reconciliation report. Opaque to
    /// the cart itself.
    public let reference: String?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        amountCents: Int,
        label: String,
        reference: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.amountCents = max(0, amountCents)
        self.label = label
        self.reference = reference
    }
}

public extension AppliedTender {
    /// Masked "Gift card ••••ABCD" label used by the apply flow. The last
    /// four chars of a 32-char hex code are enough to let the cashier
    /// correlate the receipt with the physical card without leaking the
    /// full code into the display.
    static func giftCardLabel(code: String) -> String {
        let suffix = String(code.suffix(4)).uppercased()
        return suffix.isEmpty ? "Gift card" : "Gift card ••••\(suffix)"
    }
}
