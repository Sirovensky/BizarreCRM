import Foundation

// MARK: - PricingRuleType

/// The type of pricing transformation a `PricingRule` performs.
///
/// Types are applied **before** discount engine rules so the engine
/// can reason about the adjusted line price.
public enum PricingRuleType: String, Codable, Sendable, Hashable, CaseIterable {
    /// Fixed bundle: N items for a fixed total price in cents (e.g. "3 for $10").
    case bulkBundle
    /// BOGO: buy `triggerQuantity` of the SKU/category, get `freeQuantity` free.
    case bogo
    /// Tiered volume pricing: different per-unit price depending on quantity bracket.
    case tieredVolume
    /// Customer-segment pricing: fixed percent off for a named customer segment.
    case segmentPrice
    /// Location-based: per-location flat percent price override (metro vs suburb etc.).
    case locationOverride
    /// Promotion window (flash sale): active only within an explicit time window;
    /// cashier sees a live countdown timer when the window is open.
    case promotionWindow
}

// MARK: - PricingTier

/// A single bracket in a tiered volume rule.
///
/// ```
/// Qty 1–4  → $10.00/unit
/// Qty 5–9  → $8.00/unit
/// Qty 10+  → $6.00/unit
/// ```
///
/// `maxQty == nil` means "and above" (the open-ended top bracket).
public struct PricingTier: Codable, Sendable, Hashable {
    /// Minimum quantity (inclusive) to trigger this tier.
    public let minQty: Int
    /// Maximum quantity (inclusive); `nil` = unbounded.
    public let maxQty: Int?
    /// Per-unit price in cents for this tier.
    public let unitPriceCents: Int

    public init(minQty: Int, maxQty: Int? = nil, unitPriceCents: Int) {
        self.minQty = minQty
        self.maxQty = maxQty
        self.unitPriceCents = unitPriceCents
    }

    /// Returns `true` when `qty` falls inside this tier's bracket.
    public func matches(qty: Int) -> Bool {
        guard qty >= minQty else { return false }
        if let max = maxQty { return qty <= max }
        return true
    }

    enum CodingKeys: String, CodingKey {
        case minQty       = "min_qty"
        case maxQty       = "max_qty"
        case unitPriceCents = "unit_price_cents"
    }
}

// MARK: - PricingRule

/// An advanced cart-level pricing rule applied **before** discount calculations.
///
/// The `PricingEngine` evaluates these rules and adjusts `CartItem.unitPrice`
/// or synthesises free-line additions before the `DiscountEngine` runs.
///
/// Lifecycle:
/// - Admin creates/edits rules via `PricingRuleEditorView`.
/// - Rules are stored on the server and fetched at POS open.
/// - `CartViewModel` calls `PricingEngine.apply(cart:rules:)` on every cart
///   mutation; the resulting `PricingResult` is stored and used to build the
///   final totals.
public struct PricingRule: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public var name: String
    public var type: PricingRuleType

    // MARK: - Scope fields (subset used depends on `type`)

    /// SKU or category this rule targets.  Required for `.bogo`, `.bulkBundle`,
    /// `.tieredVolume`, `.segmentPrice` by-SKU.  Empty = all items.
    public var targetSku: String?
    /// Category name used as an alternative matcher when `targetSku` is nil.
    public var targetCategory: String?
    /// Customer segment name for `.segmentPrice` rules.
    public var targetSegment: String?

    // MARK: - bulkBundle fields

    /// Number of items the bundle requires (e.g. 3 for "3 for $10").
    public var bundleQuantity: Int?
    /// Total price of the bundle in cents (e.g. 1000 for $10.00).
    public var bundlePriceCents: Int?

    // MARK: - bogo fields

    /// Number of items the customer must buy to trigger BOGO.
    public var triggerQuantity: Int?
    /// Number of free items the customer receives per trigger.
    public var freeQuantity: Int?

    // MARK: - tieredVolume fields

    /// Ordered tiers (lowest minQty first).
    public var tiers: [PricingTier]?

    // MARK: - segmentPrice fields

    /// Percent discount for the segment (0.0–1.0).
    public var segmentDiscountPercent: Double?

    // MARK: - locationOverride fields

    /// Location slug this rule applies to (e.g. `"metro-nyc"`).
    /// `nil` = applies to all locations (use `targetSku`/`targetCategory` for item scoping).
    public var targetLocationSlug: String?
    /// Flat percent price override for the location (0.0–1.0).
    /// A value of `0.05` means items are 5 % cheaper at this location.
    public var locationDiscountPercent: Double?

    // MARK: - promotionWindow fields

    /// Whether the promotion is currently live (toggled by admin).
    /// `validFrom`/`validTo` control the window; this flag provides a manual on/off override.
    public var promotionActive: Bool
    /// Human-readable flash-sale label shown to the cashier during the window,
    /// e.g. `"Summer Flash Sale – 20% off accessories"`.
    public var promotionLabel: String?
    /// Discount percent for the promotion window (0.0–1.0).
    public var promotionDiscountPercent: Double?

    // MARK: - Validity

    public var validFrom: Date?
    public var validTo: Date?
    public var enabled: Bool

    // MARK: - Priority (lower = evaluated first)

    /// Evaluation priority — lower integer wins (first matching rule wins per §16 conflict
    /// resolution). Default `0` = highest priority. Used by `PricingRulesListView` drag-to-reorder.
    public var priority: Int

    // MARK: - Init

    public init(
        id: String,
        name: String,
        type: PricingRuleType,
        targetSku: String? = nil,
        targetCategory: String? = nil,
        targetSegment: String? = nil,
        bundleQuantity: Int? = nil,
        bundlePriceCents: Int? = nil,
        triggerQuantity: Int? = nil,
        freeQuantity: Int? = nil,
        tiers: [PricingTier]? = nil,
        segmentDiscountPercent: Double? = nil,
        targetLocationSlug: String? = nil,
        locationDiscountPercent: Double? = nil,
        promotionActive: Bool = false,
        promotionLabel: String? = nil,
        promotionDiscountPercent: Double? = nil,
        validFrom: Date? = nil,
        validTo: Date? = nil,
        enabled: Bool = true,
        priority: Int = 0
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.targetSku = targetSku
        self.targetCategory = targetCategory
        self.targetSegment = targetSegment
        self.bundleQuantity = bundleQuantity
        self.bundlePriceCents = bundlePriceCents
        self.triggerQuantity = triggerQuantity
        self.freeQuantity = freeQuantity
        self.tiers = tiers
        self.segmentDiscountPercent = segmentDiscountPercent
        self.targetLocationSlug = targetLocationSlug
        self.locationDiscountPercent = locationDiscountPercent
        self.promotionActive = promotionActive
        self.promotionLabel = promotionLabel
        self.promotionDiscountPercent = promotionDiscountPercent
        self.validFrom = validFrom
        self.validTo = validTo
        self.enabled = enabled
        self.priority = priority
    }

    // MARK: - Validity helper

    public func isValid(at date: Date = .now) -> Bool {
        guard enabled else { return false }
        if let from = validFrom, date < from { return false }
        if let to = validTo, date > to { return false }
        return true
    }

    enum CodingKeys: String, CodingKey {
        case id, name, type, enabled, tiers, priority
        case targetSku                  = "target_sku"
        case targetCategory             = "target_category"
        case targetSegment              = "target_segment"
        case bundleQuantity             = "bundle_quantity"
        case bundlePriceCents           = "bundle_price_cents"
        case triggerQuantity            = "trigger_quantity"
        case freeQuantity               = "free_quantity"
        case segmentDiscountPercent     = "segment_discount_percent"
        case targetLocationSlug         = "target_location_slug"
        case locationDiscountPercent    = "location_discount_percent"
        case promotionActive            = "promotion_active"
        case promotionLabel             = "promotion_label"
        case promotionDiscountPercent   = "promotion_discount_percent"
        case validFrom                  = "valid_from"
        case validTo                    = "valid_to"
    }

    // MARK: - Computed: promotion countdown

    /// How many seconds remain in an active promotion window.
    /// Returns `nil` when `validTo` is not set or the window has closed.
    public func promotionSecondsRemaining(now: Date = .now) -> TimeInterval? {
        guard promotionActive, type == .promotionWindow,
              let end = validTo, end > now else { return nil }
        return end.timeIntervalSince(now)
    }

    /// Whether this is a promotion-window rule that is currently live.
    public func isPromotionLive(now: Date = .now) -> Bool {
        guard type == .promotionWindow, promotionActive else { return false }
        return isValid(at: now)
    }
}
