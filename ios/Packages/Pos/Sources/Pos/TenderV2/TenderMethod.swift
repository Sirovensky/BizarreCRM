/// §D — TenderMethod enum for the v2 tender two-step UI.
///
/// This is distinct from `TenderKind` (v1) so the new flow can evolve
/// independently. Both live in the Pos package; v1 files are untouched.
///
/// `apiValue` mirrors the `payment_methods.name` values the server expects
/// in `POST /api/v1/pos/transaction` `payment_method` / `payments[].method`.
public enum TenderMethod: String, CaseIterable, Sendable, Hashable, Identifiable {
    case card
    case cash
    case giftCard
    case storeCredit

    public var id: String { rawValue }

    /// Human-readable label shown in method picker tiles and receipts.
    public var displayName: String {
        switch self {
        case .card:        return "Card"
        case .cash:        return "Cash"
        case .giftCard:    return "Gift card"
        case .storeCredit: return "Store credit"
        }
    }

    /// SF Symbol name for the tile icon.
    public var systemImage: String {
        switch self {
        case .card:        return "creditcard"
        case .cash:        return "banknote"
        case .giftCard:    return "giftcard"
        case .storeCredit: return "person.badge.clock"
        }
    }

    /// Value sent to the server's `payment_method` / `payments[].method` field.
    /// These must match rows in the `payment_methods` table.
    public var apiValue: String {
        switch self {
        case .card:        return "credit_card"
        case .cash:        return "cash"
        case .giftCard:    return "gift_card"
        case .storeCredit: return "store_credit"
        }
    }

    /// Whether this method is actionable in the current build without
    /// additional hardware or entitlements.
    ///
    /// Card is gated on the ProximityReader entitlement (TODO: Tap-to-Pay
    /// integration pending — see `PosCardAmountView.swift`).
    public var isReady: Bool {
        switch self {
        case .cash:        return true
        case .giftCard:    return true
        case .storeCredit: return true
        case .card:        return false  // TODO: ProximityReader entitlement pending
        }
    }

    /// Short hint shown inside tiles for not-yet-ready methods.
    public var notReadyHint: String? {
        switch self {
        case .card: return "Tap to Pay (coming soon)"
        default:    return nil
        }
    }
}
