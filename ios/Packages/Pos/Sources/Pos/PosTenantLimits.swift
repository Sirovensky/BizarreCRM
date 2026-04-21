import Foundation

/// §16.11 — Tenant-level limits that control when a manager PIN is required.
///
/// Values are read from `UserDefaults.standard` on every access so that a
/// future server-sync pass (e.g. via `PATCH /pos/settings`) can update them
/// without a re-deploy.  The key names are stable — do NOT rename them once
/// shipped, as they become a persistent contract.
///
/// Server sync is intentionally NOT wired here yet.  When the endpoint lands,
/// the sync handler should write into `UserDefaults` using the same keys and
/// the UI will automatically see the new limits on the next POS open.
public struct PosTenantLimits: Sendable, Equatable, Codable {

    // MARK: - Discount limits

    /// Maximum percentage discount (0–100) a cashier can apply without a manager PIN.
    /// E.g. `10` means 10%; anything above triggers `ManagerPinSheet`.
    public let maxCashierDiscountPercent: Double

    /// Maximum fixed-cents discount a cashier can apply without a manager PIN.
    /// E.g. `2000` means $20.00.
    public let maxCashierDiscountCents: Int

    // MARK: - Price override threshold

    /// If |originalPrice − newPrice| ≥ this value in cents, a manager PIN is required.
    /// Default 5000 = $50.00.
    public let priceOverrideThresholdCents: Int

    // MARK: - Void / No-sale gates

    /// When `true`, voiding any line requires manager PIN approval.
    public let voidRequiresManager: Bool

    /// When `true`, opening the cash drawer without a sale requires manager PIN + reason.
    public let noSaleRequiresManager: Bool

    // MARK: - Init

    public init(
        maxCashierDiscountPercent: Double,
        maxCashierDiscountCents: Int,
        priceOverrideThresholdCents: Int,
        voidRequiresManager: Bool,
        noSaleRequiresManager: Bool
    ) {
        self.maxCashierDiscountPercent = maxCashierDiscountPercent
        self.maxCashierDiscountCents = maxCashierDiscountCents
        self.priceOverrideThresholdCents = priceOverrideThresholdCents
        self.voidRequiresManager = voidRequiresManager
        self.noSaleRequiresManager = noSaleRequiresManager
    }

    // MARK: - Factory defaults

    /// The conservative production defaults used until a tenant configures their own.
    ///
    /// Judgment call: 10% / $20 are industry-standard cashier discount caps that
    /// prevent most opportunistic theft while still allowing common promotional
    /// discounts without friction.  Void and no-sale both default to manager-gated
    /// because those are the highest-risk loss vectors.
    public static let `default` = PosTenantLimits(
        maxCashierDiscountPercent: 10,
        maxCashierDiscountCents: 2000,
        priceOverrideThresholdCents: 5000,
        voidRequiresManager: true,
        noSaleRequiresManager: true
    )

    // MARK: - UserDefaults persistence

    private enum Keys {
        static let maxCashierDiscountPercent  = "pos.limits.maxDiscountPercent"
        static let maxCashierDiscountCents    = "pos.limits.maxDiscountCents"
        static let priceOverrideThreshold     = "pos.limits.priceOverrideThreshold"
        static let voidRequiresManager        = "pos.limits.voidRequiresManager"
        static let noSaleRequiresManager      = "pos.limits.noSaleRequiresManager"
    }

    /// Load limits from `UserDefaults`, falling back to `.default` for any missing key.
    /// Called by POS screens on each sheet presentation so an in-flight server update
    /// is picked up without restarting the app.
    public static func current() -> PosTenantLimits {
        let ud = UserDefaults.standard
        return PosTenantLimits(
            maxCashierDiscountPercent: ud.object(forKey: Keys.maxCashierDiscountPercent)
                .flatMap { $0 as? Double } ?? `default`.maxCashierDiscountPercent,
            maxCashierDiscountCents: ud.object(forKey: Keys.maxCashierDiscountCents)
                .flatMap { $0 as? Int } ?? `default`.maxCashierDiscountCents,
            priceOverrideThresholdCents: ud.object(forKey: Keys.priceOverrideThreshold)
                .flatMap { $0 as? Int } ?? `default`.priceOverrideThresholdCents,
            voidRequiresManager: ud.object(forKey: Keys.voidRequiresManager)
                .flatMap { $0 as? Bool } ?? `default`.voidRequiresManager,
            noSaleRequiresManager: ud.object(forKey: Keys.noSaleRequiresManager)
                .flatMap { $0 as? Bool } ?? `default`.noSaleRequiresManager
        )
    }

    /// Persist limits (called by the server-sync handler once the endpoint ships).
    public static func persist(_ limits: PosTenantLimits) {
        let ud = UserDefaults.standard
        ud.set(limits.maxCashierDiscountPercent, forKey: Keys.maxCashierDiscountPercent)
        ud.set(limits.maxCashierDiscountCents,   forKey: Keys.maxCashierDiscountCents)
        ud.set(limits.priceOverrideThresholdCents, forKey: Keys.priceOverrideThreshold)
        ud.set(limits.voidRequiresManager,       forKey: Keys.voidRequiresManager)
        ud.set(limits.noSaleRequiresManager,     forKey: Keys.noSaleRequiresManager)
    }
}
