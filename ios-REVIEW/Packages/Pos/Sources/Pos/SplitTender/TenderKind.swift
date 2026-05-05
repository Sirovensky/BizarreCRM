/// §16.5 — Tender method kinds available at checkout.
///
/// Only `.cash` is available without hardware pairing (BlockChyp terminal
/// is Phase 5). Non-cash methods show an "unavailable" banner in the tender
/// select sheet and cannot be confirmed.
public enum TenderKind: String, CaseIterable, Sendable, Hashable {
    case cash
    case card
    case giftCard
    case storeCredit

    /// Human-readable label for display.
    public var displayName: String {
        switch self {
        case .cash:        return "Cash"
        case .card:        return "Card"
        case .giftCard:    return "Gift card"
        case .storeCredit: return "Store credit"
        }
    }

    /// SF Symbol name for the tile icon.
    public var systemImage: String {
        switch self {
        case .cash:        return "banknote"
        case .card:        return "creditcard"
        case .giftCard:    return "giftcard"
        case .storeCredit: return "person.badge.clock"
        }
    }

    /// Value sent to the server's `payment_method` field.
    public var apiValue: String {
        switch self {
        case .cash:        return "cash"
        case .card:        return "credit_card"
        case .giftCard:    return "gift_card"
        case .storeCredit: return "store_credit"
        }
    }

    /// Only cash is available without a paired BlockChyp terminal.
    public var isAvailableWithoutHardware: Bool {
        self == .cash
    }

    /// Message to surface in the tender-select sheet for hardware-gated methods.
    /// Returns `nil` for cash (always available).
    public var hardwareRequiredMessage: String? {
        guard !isAvailableWithoutHardware else { return nil }
        return "\(displayName) requires a paired payment terminal. Pair a terminal in Settings → Hardware to enable this method."
    }
}
