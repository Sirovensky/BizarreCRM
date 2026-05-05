import Foundation

/// §16 — POS pricing-rules CRUD + reorder endpoint wrappers.
///
/// Server routes (all under `/api/v1/pos/pricing-rules`):
///   GET    /pos/pricing-rules           → `{ success, data: [PricingRuleDTO] }`
///   POST   /pos/pricing-rules           → `{ success, data: PricingRuleDTO }`
///   PUT    /pos/pricing-rules/:id       → `{ success, data: PricingRuleDTO }`
///   DELETE /pos/pricing-rules/:id       → `{ success }`
///   PATCH  /pos/pricing-rules/order     → `{ success }` — batch priority update

// MARK: - DTOs

/// Wire-format representation of a single pricing rule from the server.
/// The `Pos` package maps this to its own `PricingRule` model; keeping
/// the DTO here keeps `Networking` free of `Pos` types.
public struct PricingRuleDTO: Codable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var type: String
    public var enabled: Bool
    public var priority: Int

    public var targetSku: String?
    public var targetCategory: String?
    public var targetSegment: String?
    public var bundleQuantity: Int?
    public var bundlePriceCents: Int?
    public var triggerQuantity: Int?
    public var freeQuantity: Int?
    public var tiers: [PricingTierDTO]?
    public var segmentDiscountPercent: Double?
    public var targetLocationSlug: String?
    public var locationDiscountPercent: Double?
    public var promotionActive: Bool
    public var promotionLabel: String?
    public var promotionDiscountPercent: Double?
    public var validFrom: Date?
    public var validTo: Date?

    public init(
        id: String,
        name: String,
        type: String,
        enabled: Bool = true,
        priority: Int = 0,
        targetSku: String? = nil,
        targetCategory: String? = nil,
        targetSegment: String? = nil,
        bundleQuantity: Int? = nil,
        bundlePriceCents: Int? = nil,
        triggerQuantity: Int? = nil,
        freeQuantity: Int? = nil,
        tiers: [PricingTierDTO]? = nil,
        segmentDiscountPercent: Double? = nil,
        targetLocationSlug: String? = nil,
        locationDiscountPercent: Double? = nil,
        promotionActive: Bool = false,
        promotionLabel: String? = nil,
        promotionDiscountPercent: Double? = nil,
        validFrom: Date? = nil,
        validTo: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.enabled = enabled
        self.priority = priority
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
    }

    enum CodingKeys: String, CodingKey {
        case id, name, type, enabled, tiers, priority
        case targetSku                = "target_sku"
        case targetCategory           = "target_category"
        case targetSegment            = "target_segment"
        case bundleQuantity           = "bundle_quantity"
        case bundlePriceCents         = "bundle_price_cents"
        case triggerQuantity          = "trigger_quantity"
        case freeQuantity             = "free_quantity"
        case segmentDiscountPercent   = "segment_discount_percent"
        case targetLocationSlug       = "target_location_slug"
        case locationDiscountPercent  = "location_discount_percent"
        case promotionActive          = "promotion_active"
        case promotionLabel           = "promotion_label"
        case promotionDiscountPercent = "promotion_discount_percent"
        case validFrom                = "valid_from"
        case validTo                  = "valid_to"
    }
}

/// Wire-format tier (mirrors `PricingTier` in the Pos package).
public struct PricingTierDTO: Codable, Sendable, Hashable {
    public let minQty: Int
    public let maxQty: Int?
    public let unitPriceCents: Int

    public init(minQty: Int, maxQty: Int? = nil, unitPriceCents: Int) {
        self.minQty = minQty
        self.maxQty = maxQty
        self.unitPriceCents = unitPriceCents
    }

    enum CodingKeys: String, CodingKey {
        case minQty         = "min_qty"
        case maxQty         = "max_qty"
        case unitPriceCents = "unit_price_cents"
    }
}

/// Body for `PATCH /pos/pricing-rules/order`.
private struct PricingRulesReorderBody: Encodable, Sendable {
    let orderedIds: [String]
    enum CodingKeys: String, CodingKey { case orderedIds = "ordered_ids" }
}

// MARK: - APIClient wrappers

public extension APIClient {

    // MARK: List

    /// `GET /api/v1/pos/pricing-rules` — fetch all rules for the tenant.
    func listPosPricingRules() async throws -> [PricingRuleDTO] {
        try await get("/api/v1/pos/pricing-rules", as: [PricingRuleDTO].self)
    }

    // MARK: Create

    /// `POST /api/v1/pos/pricing-rules` — create a new rule.
    func createPosPricingRule(_ rule: PricingRuleDTO) async throws -> PricingRuleDTO {
        try await post("/api/v1/pos/pricing-rules", body: rule, as: PricingRuleDTO.self)
    }

    // MARK: Update

    /// `PUT /api/v1/pos/pricing-rules/:id` — full update of an existing rule.
    func updatePosPricingRule(_ rule: PricingRuleDTO) async throws -> PricingRuleDTO {
        try await put("/api/v1/pos/pricing-rules/\(rule.id)", body: rule, as: PricingRuleDTO.self)
    }

    // MARK: Delete

    /// `DELETE /api/v1/pos/pricing-rules/:id` — delete a rule.
    func deletePosPricingRule(id: String) async throws {
        try await delete("/api/v1/pos/pricing-rules/\(id)")
    }

    // MARK: Reorder

    /// `PATCH /api/v1/pos/pricing-rules/order` — update priority order server-side.
    /// `orderedIds` is the full rule-id array in desired ascending priority order.
    func reorderPosPricingRules(orderedIds: [String]) async throws {
        let body = PricingRulesReorderBody(orderedIds: orderedIds)
        _ = try await patch("/api/v1/pos/pricing-rules/order", body: body, as: PosEmptyResponse.self)
    }
}
