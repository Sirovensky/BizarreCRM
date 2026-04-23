import Foundation

/// §16.6 — Payment method choices shown on the tender-select sheet.
///
/// Only `cash` is fully functional in this phase; `card`, `giftCard`, and
/// `storeCredit` show a "requires hardware paired" banner and do not allow
/// checkout to complete. `blockchyp` (card) requires §17.3 terminal pairing.
public enum TenderKind: String, CaseIterable, Sendable, Hashable {
    case cash
    case card
    case giftCard
    case storeCredit

    public var displayName: String {
        switch self {
        case .cash:        return "Cash"
        case .card:        return "Card"
        case .giftCard:    return "Gift card"
        case .storeCredit: return "Store credit"
        }
    }

    public var systemImage: String {
        switch self {
        case .cash:        return "banknote"
        case .card:        return "creditcard"
        case .giftCard:    return "giftcard"
        case .storeCredit: return "person.badge.clock"
        }
    }

    /// API value sent in `payment_method` to `POST /pos/transaction`.
    public var apiValue: String {
        switch self {
        case .cash:        return "cash"
        case .card:        return "credit_card"
        case .giftCard:    return "gift_card"
        case .storeCredit: return "store_credit"
        }
    }

    /// `true` when this tender can complete a sale without hardware pairing.
    /// Only cash is functional in Phase 5 before BlockChyp SDK lands (§17).
    public var isAvailableWithoutHardware: Bool {
        self == .cash
    }

    /// Human-readable reason displayed when `isAvailableWithoutHardware` is `false`.
    public var hardwareRequiredMessage: String? {
        switch self {
        case .cash:        return nil
        case .card:        return "Card payments require a BlockChyp terminal paired in Settings → Hardware."
        case .giftCard:    return "Gift card redemption requires an internet connection and the Hardware add-on."
        case .storeCredit: return "Store credit requires the customer to be looked up first."
        }
    }
}
