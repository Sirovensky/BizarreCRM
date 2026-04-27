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
    /// §16.6 — Paper check: check # + bank + memo; no payment auth; goes to A/R.
    case check
    /// §16.6 — Account credit / net-30: role-gated; only if customer has terms set;
    /// adds the full amount to the customer's open balance (A/R). No payment auth.
    case accountCredit

    public var id: String { rawValue }

    /// Human-readable label shown in method picker tiles and receipts.
    public var displayName: String {
        switch self {
        case .card:          return "Card"
        case .cash:          return "Cash"
        case .giftCard:      return "Gift card"
        case .storeCredit:   return "Store credit"
        case .check:         return "Check"
        case .accountCredit: return "Account / Net-30"
        }
    }

    /// SF Symbol name for the tile icon.
    /// Mockup screen 5a: 💳 card, 💵 cash, 🎁 gift card, 💸 store credit.
    /// `.fill` variants match the mockup's solid emoji weight.
    public var systemImage: String {
        switch self {
        case .card:          return "creditcard.fill"
        case .cash:          return "banknote.fill"
        case .giftCard:      return "giftcard.fill"
        case .storeCredit:   return "dollarsign.circle.fill"
        case .check:         return "checkmark.seal.fill"
        case .accountCredit: return "building.columns.fill"
        }
    }

    /// Value sent to the server's `payment_method` / `payments[].method` field.
    /// These must match rows in the `payment_methods` table.
    public var apiValue: String {
        switch self {
        case .card:          return "credit_card"
        case .cash:          return "cash"
        case .giftCard:      return "gift_card"
        case .storeCredit:   return "store_credit"
        case .check:         return "check"
        case .accountCredit: return "account_credit"
        }
    }

    /// Whether this method is actionable in the current build without
    /// additional hardware or entitlements.
    ///
    /// Card is gated on the ProximityReader entitlement (TODO: Tap-to-Pay
    /// integration pending — see `PosCardAmountView.swift`).
    public var isReady: Bool {
        switch self {
        case .cash:          return true
        case .giftCard:      return true
        case .storeCredit:   return true
        case .check:         return true
        case .accountCredit: return true   // §16.6 role-gated at call site
        case .card:          return false  // TODO: ProximityReader entitlement pending
        }
    }

    /// Short hint shown inside tiles for not-yet-ready methods.
    /// Kept for accessibility hint only — the tile subtitle always shows
    /// `tileSubtitle` to match the mockup layout exactly.
    public var notReadyHint: String? {
        switch self {
        case .card: return "Tap to Pay — coming soon"
        default:    return nil
        }
    }

    /// Whether this method requires manager PIN / role check before display.
    /// The caller is responsible for gating; this flag drives UI hints only.
    public var requiresRoleGate: Bool {
        self == .accountCredit
    }

    /// Subtitle shown on every method tile (ready or not) — matching mockup 5a/4a.
    public var tileSubtitle: String {
        switch self {
        case .card:          return "Tap to Pay"
        case .cash:          return "Enter amount"
        case .giftCard:      return "Scan / enter"
        case .storeCredit:   return "Avail. balance"
        case .check:         return "Check # + bank"
        case .accountCredit: return "Net-30 · A/R"
        }
    }

    /// Whether this method is gated on hardware / entitlements not yet active.
    /// When true the tile still shows the default `tileSubtitle`, not the
    /// "coming soon" hint — the tile is just dimmed and non-navigable.
    ///
    /// NOTE: card is listed as not-ready while ProximityReader entitlement is
    /// pending, but the mockup shows the tile with its normal subtitle so we
    /// preserve that display and only grey-out the tile slightly.
    public var isReadySoon: Bool {
        self == .card
    }

    /// Whether this method requires an additional details sheet rather than
    /// a simple numeric amount entry.
    /// - Note: `.accountCredit` uses `PosAccountCreditTenderSheet`; `.check`
    ///   uses `PosCheckTenderSheet`.
    public var requiresDetailsSheet: Bool {
        self == .check || self == .accountCredit
    }
}
