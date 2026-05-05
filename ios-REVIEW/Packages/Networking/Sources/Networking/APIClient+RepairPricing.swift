import Foundation

/// §43 — Repair-pricing catalog API extensions on `APIClient`.
///
/// Server routes (all under `/api/v1/repair-pricing`, registered in
/// `packages/server/src/routes/repairPricing.routes.ts`):
///
///   GET  /repair-pricing/services            → `{ success, data: [RepairServiceRow] }`
///   GET  /repair-pricing/prices              → `{ success, data: [RepairPriceRow] }`
///   GET  /repair-pricing/lookup              → `{ success, data: RepairPricingLookupResult? }`
///   GET  /repair-pricing/adjustments         → `{ success, data: { flat, pct } }`
///   GET  /repair-pricing/auto-margin-settings → server-owned calculator policy
///
/// The `DeviceTemplatesEndpoints.swift` file (also in this package) owns the
/// `DeviceTemplate` / `RepairService` DTOs and `listDeviceTemplates` /
/// `getDeviceTemplate` / `listRepairServices`.  This file adds the
/// **lookup** endpoint (used in POS check-in) and its response DTO so
/// that callers outside the RepairPricing package can resolve a
/// (device_model_id, repair_service_id) pair into a fully-adjusted price.

// MARK: - DTOs

/// A single grade tier inside a `RepairPricingLookupResult`.
/// Mirrors `repair_price_grades` + joined inventory/catalog columns.
public struct RepairPricingGrade: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    /// Grade key, e.g. "aftermarket", "oem", "used"
    public let grade: String
    /// Human-readable label, e.g. "Aftermarket"
    public let gradeLabel: String
    /// Part price in cents (base, before adjustment)
    public let partPriceCents: Int
    /// Labour price override in cents, if set for this grade
    public let laborPriceOverrideCents: Int?
    /// Effective labour price (adjusted) injected by the server
    public let effectiveLaborPriceCents: Int
    /// Inventory item name if linked
    public let inventoryItemName: String?
    /// Whether linked inventory item is in stock
    public let inventoryInStock: Int?
    /// Supplier catalog item name if linked
    public let catalogItemName: String?
    /// Supplier catalog URL if linked
    public let catalogUrl: String?
    /// Whether this is the default grade for the price row
    public let isDefault: Int
    public let sortOrder: Int

    public init(
        id: Int64,
        grade: String,
        gradeLabel: String,
        partPriceCents: Int = 0,
        laborPriceOverrideCents: Int? = nil,
        effectiveLaborPriceCents: Int = 0,
        inventoryItemName: String? = nil,
        inventoryInStock: Int? = nil,
        catalogItemName: String? = nil,
        catalogUrl: String? = nil,
        isDefault: Int = 0,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.grade = grade
        self.gradeLabel = gradeLabel
        self.partPriceCents = partPriceCents
        self.laborPriceOverrideCents = laborPriceOverrideCents
        self.effectiveLaborPriceCents = effectiveLaborPriceCents
        self.inventoryItemName = inventoryItemName
        self.inventoryInStock = inventoryInStock
        self.catalogItemName = catalogItemName
        self.catalogUrl = catalogUrl
        self.isDefault = isDefault
        self.sortOrder = sortOrder
    }

    enum CodingKeys: String, CodingKey {
        case id
        case grade
        case gradeLabel             = "grade_label"
        case partPriceCents         = "part_price"
        case laborPriceOverrideCents = "labor_price_override"
        case effectiveLaborPriceCents = "effective_labor_price"
        case inventoryItemName      = "inventory_item_name"
        case inventoryInStock       = "inventory_in_stock"
        case catalogItemName        = "catalog_item_name"
        case catalogUrl             = "catalog_url"
        case isDefault              = "is_default"
        case sortOrder              = "sort_order"
    }
}

/// Global pricing adjustments applied by the server.
public struct RepairPricingAdjustments: Decodable, Sendable, Hashable, Equatable {
    /// Flat dollar adjustment (may be negative), in dollars (not cents)
    public let flat: Double
    /// Percentage adjustment applied before flat (e.g. 10 = +10%)
    public let pct: Double

    public init(flat: Double = 0, pct: Double = 0) {
        self.flat = flat
        self.pct = pct
    }
}

/// Full server response from `GET /repair-pricing/lookup`.
///
/// `nil` from the server (device/service combo has no price row) is
/// surfaced as a `nil` return from `lookupRepairPrice(...)`.
public struct RepairPricingLookupResult: Decodable, Sendable, Identifiable, Hashable {
    /// repair_prices.id
    public let id: Int64
    public let deviceModelId: Int64
    public let repairServiceId: Int64
    public let deviceModelName: String
    public let manufacturerName: String
    public let repairServiceName: String
    public let repairServiceSlug: String
    /// Base labour price in cents (before adjustments)
    public let baseLaborPriceCents: Int
    /// Adjusted labour price in cents (after flat + pct)
    public let laborPriceCents: Int
    /// The applied global adjustments
    public let adjustments: RepairPricingAdjustments
    /// Grade tiers with per-grade effective prices
    public let grades: [RepairPricingGrade]
    /// Default grade key, e.g. "aftermarket"
    public let defaultGrade: String
    public let isActive: Int

    public init(
        id: Int64,
        deviceModelId: Int64,
        repairServiceId: Int64,
        deviceModelName: String,
        manufacturerName: String,
        repairServiceName: String,
        repairServiceSlug: String,
        baseLaborPriceCents: Int,
        laborPriceCents: Int,
        adjustments: RepairPricingAdjustments = RepairPricingAdjustments(),
        grades: [RepairPricingGrade] = [],
        defaultGrade: String = "aftermarket",
        isActive: Int = 1
    ) {
        self.id = id
        self.deviceModelId = deviceModelId
        self.repairServiceId = repairServiceId
        self.deviceModelName = deviceModelName
        self.manufacturerName = manufacturerName
        self.repairServiceName = repairServiceName
        self.repairServiceSlug = repairServiceSlug
        self.baseLaborPriceCents = baseLaborPriceCents
        self.laborPriceCents = laborPriceCents
        self.adjustments = adjustments
        self.grades = grades
        self.defaultGrade = defaultGrade
        self.isActive = isActive
    }

    enum CodingKeys: String, CodingKey {
        case id
        case deviceModelId      = "device_model_id"
        case repairServiceId    = "repair_service_id"
        case deviceModelName    = "device_model_name"
        case manufacturerName   = "manufacturer_name"
        case repairServiceName  = "repair_service_name"
        case repairServiceSlug  = "repair_service_slug"
        case baseLaborPriceCents = "base_labor_price"
        case laborPriceCents    = "labor_price"
        case adjustments
        case grades
        case defaultGrade       = "default_grade"
        case isActive           = "is_active"
    }
}

// MARK: - Dynamic pricing matrix DTOs

public enum RepairPricingTierKey: String, Codable, Sendable, Hashable, CaseIterable {
    case tierA = "tier_a"
    case tierB = "tier_b"
    case tierC = "tier_c"
    case unknown
}

public struct RepairPricingTierThresholds: Codable, Sendable, Hashable {
    public let tierAYears: Int
    public let tierBYears: Int

    public init(tierAYears: Int, tierBYears: Int) {
        self.tierAYears = tierAYears
        self.tierBYears = tierBYears
    }
}

public struct RepairPricingTierDescriptor: Decodable, Sendable, Hashable {
    public let key: RepairPricingTierKey
    public let label: String
    public let maxAgeYears: Int?
    public let deviceCount: Int?
}

public struct RepairPricingTiersResponse: Decodable, Sendable, Hashable {
    public let thresholds: RepairPricingTierThresholds
    public let tiers: [RepairPricingTierDescriptor]
}

public struct RepairPricingMatrixService: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let name: String
    public let slug: String
    public let category: String?
    public let description: String?
    public let isActive: Int
    public let sortOrder: Int
}

public struct RepairPricingMatrixPrice: Decodable, Sendable, Hashable {
    public let repairServiceId: Int64
    public let repairServiceName: String
    public let repairServiceSlug: String
    public let serviceCategory: String?
    public let priceId: Int64?
    public let laborPrice: Double?
    public let defaultGrade: String?
    public let isActive: Int?
    public let isCustom: Int
    public let tierLabel: RepairPricingTierKey?
    public let profitEstimate: Double?
    public let profitStaleAt: String?
    public let autoMarginEnabled: Int
    public let lastSupplierCost: Double?
    public let lastSupplierSeenAt: String?
    public let suggestedLaborPrice: Double?
    public let updatedAt: String?
}

public struct RepairPricingMatrixDevice: Decodable, Sendable, Hashable {
    public let deviceModelId: Int64
    public let deviceModelName: String
    public let deviceModelSlug: String
    public let manufacturerId: Int64
    public let manufacturerName: String
    public let category: String
    public let releaseYear: Int?
    public let tier: RepairPricingTierKey
    public let tierLabel: String
    public let isPopular: Int
    public let prices: [RepairPricingMatrixPrice]
}

public struct RepairPricingMatrixResponse: Decodable, Sendable, Hashable {
    public let thresholds: RepairPricingTierThresholds
    public let services: [RepairPricingMatrixService]
    public let devices: [RepairPricingMatrixDevice]
}

public struct RepairPricingTierApplyRequest: Encodable, Sendable {
    public let repairServiceId: Int64
    public let tier: RepairPricingTierKey
    public let laborPrice: Double
    public let category: String?
    public let overwriteCustom: Bool?

    public init(
        repairServiceId: Int64,
        tier: RepairPricingTierKey,
        laborPrice: Double,
        category: String? = nil,
        overwriteCustom: Bool? = nil
    ) {
        self.repairServiceId = repairServiceId
        self.tier = tier
        self.laborPrice = laborPrice
        self.category = category
        self.overwriteCustom = overwriteCustom
    }

    enum CodingKeys: String, CodingKey {
        case repairServiceId = "repair_service_id"
        case tier
        case laborPrice = "labor_price"
        case category
        case overwriteCustom = "overwrite_custom"
    }
}

public struct RepairPricingTierApplyResult: Decodable, Sendable, Hashable {
    public let tier: RepairPricingTierKey
    public let tierLabel: String
    public let repairServiceId: Int64
    public let laborPrice: Double
    public let matchedDevices: Int
    public let inserted: Int
    public let updated: Int
    public let skippedCustom: Int
}

public typealias RepairPricingSeedPricing = [String: [String: Double]]

public struct RepairPricingSeedDefaultsRequest: Encodable, Sendable {
    public let category: String?
    public let pricing: RepairPricingSeedPricing?
    public let overwriteCustom: Bool?

    public init(
        category: String? = "phone",
        pricing: RepairPricingSeedPricing? = nil,
        overwriteCustom: Bool? = nil
    ) {
        self.category = category
        self.pricing = pricing
        self.overwriteCustom = overwriteCustom
    }

    enum CodingKeys: String, CodingKey {
        case category
        case pricing
        case overwriteCustom = "overwrite_custom"
    }
}

public struct RepairPricingSeedDefaultsResponse: Decodable, Sendable, Hashable {
    public struct Service: Decodable, Sendable, Hashable {
        public let serviceKey: String
        public let repairServiceId: Int64?
        public let repairServiceSlug: String?
        public let missing: Bool
        public let tiers: [RepairPricingTierApplyResult]
    }

    public struct Summary: Decodable, Sendable, Hashable {
        public let servicesMatched: Int
        public let servicesMissing: Int
        public let matchedDevices: Int
        public let inserted: Int
        public let updated: Int
        public let skippedCustom: Int
    }

    public let category: String
    public let defaults: RepairPricingSeedPricing
    public let services: [Service]
    public let summary: Summary
}

public enum RepairPricingRoundingMode: String, Codable, Sendable, Hashable, CaseIterable {
    case none
    case ending99 = "ending_99"
    case wholeDollar = "whole_dollar"
    case ending98 = "ending_98"
}

public enum RepairPricingAutoMarginBasis: String, Codable, Sendable, Hashable, CaseIterable {
    case grossMargin = "gross_margin"
    case markup
}

public enum RepairPricingAutoMarginPreset: String, Codable, Sendable, Hashable, CaseIterable {
    case highTraffic = "high_traffic"
    case midTraffic = "mid_traffic"
    case lowTraffic = "low_traffic"
    // Legacy preset names are accepted for older tenants and web builds.
    case value
    case balanced
    case premium
    case custom
}

public enum RepairPricingAutoMarginTargetType: String, Codable, Sendable, Hashable, CaseIterable {
    case percent
    case fixedAmount = "fixed_amount"
}

public enum RepairPricingAutoMarginRuleScope: String, Codable, Sendable, Hashable, CaseIterable {
    case global
    case repairService = "repair_service"
    case tier
    case device
}

public struct RepairPricingAutoMarginRule: Codable, Sendable, Hashable, Identifiable {
    public let id: String?
    public let scope: RepairPricingAutoMarginRuleScope
    public let label: String?
    public let repairServiceId: Int64?
    public let repairServiceSlug: String?
    public let tier: RepairPricingTierKey?
    public let deviceModelId: Int64?
    public var targetType: RepairPricingAutoMarginTargetType?
    public var targetMarginPct: Double
    public var targetProfitAmount: Double?
    public var calculationBasis: RepairPricingAutoMarginBasis?
    public var roundingMode: RepairPricingRoundingMode?
    public var capPct: Double?
    public var enabled: Bool?

    public init(
        id: String? = nil,
        scope: RepairPricingAutoMarginRuleScope,
        label: String? = nil,
        repairServiceId: Int64? = nil,
        repairServiceSlug: String? = nil,
        tier: RepairPricingTierKey? = nil,
        deviceModelId: Int64? = nil,
        targetType: RepairPricingAutoMarginTargetType? = .percent,
        targetMarginPct: Double,
        targetProfitAmount: Double? = nil,
        calculationBasis: RepairPricingAutoMarginBasis? = nil,
        roundingMode: RepairPricingRoundingMode? = nil,
        capPct: Double? = nil,
        enabled: Bool? = true
    ) {
        self.id = id
        self.scope = scope
        self.label = label
        self.repairServiceId = repairServiceId
        self.repairServiceSlug = repairServiceSlug
        self.tier = tier
        self.deviceModelId = deviceModelId
        self.targetType = targetType
        self.targetMarginPct = targetMarginPct
        self.targetProfitAmount = targetProfitAmount
        self.calculationBasis = calculationBasis
        self.roundingMode = roundingMode
        self.capPct = capPct
        self.enabled = enabled
    }

    enum CodingKeys: String, CodingKey {
        case id
        case scope
        case label
        case repairServiceId = "repair_service_id"
        case repairServiceSlug = "repair_service_slug"
        case tier
        case deviceModelId = "device_model_id"
        case targetType = "target_type"
        case targetMarginPct = "target_margin_pct"
        case targetProfitAmount = "target_profit_amount"
        case calculationBasis = "calculation_basis"
        case roundingMode = "rounding_mode"
        case capPct = "cap_pct"
        case enabled
    }
}

public struct RepairPricingAutoMarginSettings: Codable, Sendable, Hashable {
    public let preset: RepairPricingAutoMarginPreset
    public let targetType: RepairPricingAutoMarginTargetType
    public let targetMarginPct: Double
    public let targetProfitAmount: Double
    public let calculationBasis: RepairPricingAutoMarginBasis
    public let roundingMode: RepairPricingRoundingMode
    public let capPct: Double
    public let rules: [RepairPricingAutoMarginRule]

    public init(
        preset: RepairPricingAutoMarginPreset = .midTraffic,
        targetType: RepairPricingAutoMarginTargetType = .percent,
        targetMarginPct: Double,
        targetProfitAmount: Double = 80,
        calculationBasis: RepairPricingAutoMarginBasis = .markup,
        roundingMode: RepairPricingRoundingMode,
        capPct: Double,
        rules: [RepairPricingAutoMarginRule] = []
    ) {
        self.preset = preset
        self.targetType = targetType
        self.targetMarginPct = targetMarginPct
        self.targetProfitAmount = targetProfitAmount
        self.calculationBasis = calculationBasis
        self.roundingMode = roundingMode
        self.capPct = capPct
        self.rules = rules
    }

    enum CodingKeys: String, CodingKey {
        case preset
        case targetType = "target_type"
        case targetMarginPct = "target_margin_pct"
        case targetProfitAmount = "target_profit_amount"
        case calculationBasis = "calculation_basis"
        case roundingMode = "rounding_mode"
        case capPct = "cap_pct"
        case rules
    }
}

public struct RepairPricingAutoMarginPreviewRequest: Encodable, Sendable {
    public let supplierCost: Double
    public let currentLaborPrice: Double?
    public let targetType: RepairPricingAutoMarginTargetType?
    public let targetMarginPct: Double?
    public let targetProfitAmount: Double?
    public let calculationBasis: RepairPricingAutoMarginBasis?
    public let roundingMode: RepairPricingRoundingMode?
    public let capPct: Double?
    public let rule: RepairPricingAutoMarginRule?

    public init(
        supplierCost: Double,
        currentLaborPrice: Double? = nil,
        targetType: RepairPricingAutoMarginTargetType? = nil,
        targetMarginPct: Double? = nil,
        targetProfitAmount: Double? = nil,
        calculationBasis: RepairPricingAutoMarginBasis? = nil,
        roundingMode: RepairPricingRoundingMode? = nil,
        capPct: Double? = nil,
        rule: RepairPricingAutoMarginRule? = nil
    ) {
        self.supplierCost = supplierCost
        self.currentLaborPrice = currentLaborPrice
        self.targetType = targetType
        self.targetMarginPct = targetMarginPct
        self.targetProfitAmount = targetProfitAmount
        self.calculationBasis = calculationBasis
        self.roundingMode = roundingMode
        self.capPct = capPct
        self.rule = rule
    }

    enum CodingKeys: String, CodingKey {
        case supplierCost = "supplier_cost"
        case currentLaborPrice = "current_labor_price"
        case targetType = "target_type"
        case targetMarginPct = "target_margin_pct"
        case targetProfitAmount = "target_profit_amount"
        case calculationBasis = "calculation_basis"
        case roundingMode = "rounding_mode"
        case capPct = "cap_pct"
        case rule
    }
}

public struct RepairPricingAutoMarginPreview: Decodable, Sendable, Hashable {
    public let supplierCost: Double
    public let currentLaborPrice: Double?
    public let targetType: RepairPricingAutoMarginTargetType
    public let targetMarginPct: Double
    public let targetProfitAmount: Double
    public let calculationBasis: RepairPricingAutoMarginBasis
    public let roundingMode: RepairPricingRoundingMode
    public let capPct: Double
    public let uncappedLaborPrice: Double
    public let roundedLaborPrice: Double
    public let cappedLaborPrice: Double?
    public let profitEstimate: Double
    public let marginPct: Double
}

public struct RepairPricingAuditRow: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let repairPriceId: Int64?
    public let deviceModelId: Int64?
    public let repairServiceId: Int64?
    public let oldLaborPrice: Double?
    public let newLaborPrice: Double?
    public let oldIsCustom: Int?
    public let newIsCustom: Int?
    public let oldTierLabel: RepairPricingTierKey?
    public let newTierLabel: RepairPricingTierKey?
    public let supplierCost: Double?
    public let profitEstimate: Double?
    public let source: String
    public let changedByUserId: Int64?
    public let importedFilename: String?
    public let note: String?
    public let createdAt: String
    public let deviceModelName: String?
    public let repairServiceName: String?
    public let changedByUsername: String?
}

public struct RepairPricingRevertResult: Decodable, Sendable, Hashable {
    public let price: RepairPriceDynamicRow
    public let tier: RepairPricingTierKey
    public let tierLabel: String
    public let defaultSource: String
}

public struct RepairPriceDynamicRow: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let deviceModelId: Int64
    public let repairServiceId: Int64
    public let laborPrice: Double
    public let defaultGrade: String?
    public let isActive: Int
    public let isCustom: Int
    public let tierLabel: RepairPricingTierKey?
    public let profitEstimate: Double?
    public let profitStaleAt: String?
    public let autoMarginEnabled: Int
    public let lastSupplierCost: Double?
    public let lastSupplierSeenAt: String?
    public let suggestedLaborPrice: Double?
    public let updatedAt: String?
}

public struct RepairPricingProfitRecomputeRequest: Encodable, Sendable {
    public let priceIds: [Int64]?
    public let autoMargin: Bool?

    public init(priceIds: [Int64]? = nil, autoMargin: Bool? = nil) {
        self.priceIds = priceIds
        self.autoMargin = autoMargin
    }

    enum CodingKeys: String, CodingKey {
        case priceIds = "price_ids"
        case autoMargin = "auto_margin"
    }
}

public struct RepairPricingProfitRecomputeResponse: Decodable, Sendable, Hashable {
    public struct Recompute: Decodable, Sendable, Hashable {
        public let processed: Int
        public let updated: Int
        public let stale: Int
    }

    public struct AutoMargin: Decodable, Sendable, Hashable {
        public let evaluated: Int
        public let adjusted: Int
        public let skipped: Int
        public let targetMarginPct: Double
        public let roundingMode: RepairPricingRoundingMode
        public let capPct: Double
    }

    public let recompute: Recompute
    public let autoMargin: AutoMargin?
}

public struct RepairPricingPriceWriteRequest: Encodable, Sendable {
    public let deviceModelId: Int64?
    public let repairServiceId: Int64?
    public let laborPrice: Double
    public let defaultGrade: String?
    public let isActive: Int?
    public let isCustom: Int?
    public let autoMarginEnabled: Int?

    public init(
        deviceModelId: Int64? = nil,
        repairServiceId: Int64? = nil,
        laborPrice: Double,
        defaultGrade: String? = "aftermarket",
        isActive: Int? = 1,
        isCustom: Int? = 1,
        autoMarginEnabled: Int? = 0
    ) {
        self.deviceModelId = deviceModelId
        self.repairServiceId = repairServiceId
        self.laborPrice = laborPrice
        self.defaultGrade = defaultGrade
        self.isActive = isActive
        self.isCustom = isCustom
        self.autoMarginEnabled = autoMarginEnabled
    }

    enum CodingKeys: String, CodingKey {
        case deviceModelId = "device_model_id"
        case repairServiceId = "repair_service_id"
        case laborPrice = "labor_price"
        case defaultGrade = "default_grade"
        case isActive = "is_active"
        case isCustom = "is_custom"
        case autoMarginEnabled = "auto_margin_enabled"
    }
}

private struct RepairPricingTierThresholdsBody: Encodable, Sendable {
    let tierAYears: Int
    let tierBYears: Int

    enum CodingKeys: String, CodingKey {
        case tierAYears = "tier_a_years"
        case tierBYears = "tier_b_years"
    }
}

private struct EmptyRepairPricingBody: Encodable, Sendable {}

// MARK: - APIClient wrappers

public extension APIClient {
    /// Resolve a (device model, repair service) pair into a fully-adjusted
    /// price result including grade tiers and global adjustments.
    ///
    /// Returns `nil` when the server has no price row for the combination
    /// (server responds `{ success: true, data: null }`).
    ///
    /// - Parameters:
    ///   - deviceModelId: `device_models.id` (numeric)
    ///   - repairServiceId: `repair_services.id` (numeric)
    func lookupRepairPrice(
        deviceModelId: Int64,
        repairServiceId: Int64
    ) async throws -> RepairPricingLookupResult? {
        let query: [URLQueryItem] = [
            URLQueryItem(name: "device_model_id",   value: String(deviceModelId)),
            URLQueryItem(name: "repair_service_id", value: String(repairServiceId))
        ]
        // Use getEnvelope so that a `{ success: true, data: null }` response
        // (no price row exists) is returned as `nil` rather than throwing
        // envelopeFailure.  The underlying `unwrap` guard rejects null data,
        // so we bypass it and read `envelope.data` directly.
        let envelope = try await getEnvelope(
            "/api/v1/repair-pricing/lookup",
            query: query,
            as: RepairPricingLookupResult.self
        )
        guard envelope.success else {
            throw APITransportError.envelopeFailure(message: envelope.message)
        }
        return envelope.data
    }

    /// Fetch the current global pricing adjustments (flat + pct).
    func fetchRepairPricingAdjustments() async throws -> RepairPricingAdjustments {
        try await get(
            "/api/v1/repair-pricing/adjustments",
            as: RepairPricingAdjustments.self
        )
    }

    /// Fetch server-owned pricing age tiers and current device counts.
    func fetchRepairPricingTiers() async throws -> RepairPricingTiersResponse {
        try await get("/api/v1/repair-pricing/tiers", as: RepairPricingTiersResponse.self)
    }

    /// Update pricing age-tier thresholds. The server remains authoritative and
    /// persists these in tenant `store_config`.
    func updateRepairPricingTiers(tierAYears: Int, tierBYears: Int) async throws -> RepairPricingTiersResponse {
        try await put(
            "/api/v1/repair-pricing/tiers",
            body: RepairPricingTierThresholdsBody(tierAYears: tierAYears, tierBYears: tierBYears),
            as: RepairPricingTiersResponse.self
        )
    }

    /// Fetch the authoritative device/service pricing matrix. This is data
    /// preparation only; feature screens decide how to present it.
    func fetchRepairPricingMatrix(
        category: String? = nil,
        manufacturerId: Int64? = nil,
        repairServiceId: Int64? = nil,
        query search: String? = nil,
        limit: Int? = nil
    ) async throws -> RepairPricingMatrixResponse {
        var items: [URLQueryItem] = []
        if let category, !category.isEmpty { items.append(URLQueryItem(name: "category", value: category)) }
        if let manufacturerId { items.append(URLQueryItem(name: "manufacturer_id", value: String(manufacturerId))) }
        if let repairServiceId { items.append(URLQueryItem(name: "repair_service_id", value: String(repairServiceId))) }
        if let search, !search.isEmpty { items.append(URLQueryItem(name: "q", value: search)) }
        if let limit { items.append(URLQueryItem(name: "limit", value: String(limit))) }
        return try await get(
            "/api/v1/repair-pricing/matrix",
            query: items.isEmpty ? nil : items,
            as: RepairPricingMatrixResponse.self
        )
    }

    /// Apply a tier labor default across matching devices. Custom cells are
    /// preserved unless `overwriteCustom` is true.
    func applyRepairPricingTier(_ request: RepairPricingTierApplyRequest) async throws -> RepairPricingTierApplyResult {
        try await post(
            "/api/v1/repair-pricing/tier-apply",
            body: request,
            as: RepairPricingTierApplyResult.self
        )
    }

    /// Create one manual spreadsheet price cell. The server stamps the row as
    /// custom pricing and records the audit event.
    func createRepairPricingPrice(_ request: RepairPricingPriceWriteRequest) async throws -> RepairPriceDynamicRow {
        try await post(
            "/api/v1/repair-pricing/prices",
            body: request,
            as: RepairPriceDynamicRow.self
        )
    }

    /// Update one manual spreadsheet price cell. Pass only server-owned row IDs
    /// discovered from the matrix endpoint.
    func updateRepairPricingPrice(
        priceId: Int64,
        request: RepairPricingPriceWriteRequest
    ) async throws -> RepairPriceDynamicRow {
        try await put(
            "/api/v1/repair-pricing/prices/\(priceId)",
            body: request,
            as: RepairPriceDynamicRow.self
        )
    }

    /// Seed day-1 tier defaults through the server-owned fan-out endpoint.
    /// Mobile setup and web setup should call this rather than writing local
    /// config keys so all devices share the same authoritative repair_prices.
    func seedRepairPricingDefaults(_ request: RepairPricingSeedDefaultsRequest = RepairPricingSeedDefaultsRequest()) async throws -> RepairPricingSeedDefaultsResponse {
        try await post(
            "/api/v1/repair-pricing/seed-defaults",
            body: request,
            as: RepairPricingSeedDefaultsResponse.self
        )
    }

    /// Fetch the server-owned auto-margin calculator policy.
    func fetchRepairPricingAutoMarginSettings() async throws -> RepairPricingAutoMarginSettings {
        try await get(
            "/api/v1/repair-pricing/auto-margin-settings",
            as: RepairPricingAutoMarginSettings.self
        )
    }

    /// Update target margin percent, rounding style, and the per-run safety cap.
    func updateRepairPricingAutoMarginSettings(_ settings: RepairPricingAutoMarginSettings) async throws -> RepairPricingAutoMarginSettings {
        try await put(
            "/api/v1/repair-pricing/auto-margin-settings",
            body: settings,
            as: RepairPricingAutoMarginSettings.self
        )
    }

    /// Preview the server's calculator without writing a repair_prices row.
    func previewRepairPricingAutoMargin(_ request: RepairPricingAutoMarginPreviewRequest) async throws -> RepairPricingAutoMarginPreview {
        try await post(
            "/api/v1/repair-pricing/auto-margin-preview",
            body: request,
            as: RepairPricingAutoMarginPreview.self
        )
    }

    /// Fetch pricing audit rows for settings/history screens.
    func fetchRepairPricingAudit(
        repairPriceId: Int64? = nil,
        deviceModelId: Int64? = nil,
        repairServiceId: Int64? = nil,
        from: String? = nil,
        to: String? = nil,
        limit: Int? = nil
    ) async throws -> [RepairPricingAuditRow] {
        var items: [URLQueryItem] = []
        if let repairPriceId { items.append(URLQueryItem(name: "repair_price_id", value: String(repairPriceId))) }
        if let deviceModelId { items.append(URLQueryItem(name: "device_model_id", value: String(deviceModelId))) }
        if let repairServiceId { items.append(URLQueryItem(name: "repair_service_id", value: String(repairServiceId))) }
        if let from { items.append(URLQueryItem(name: "from", value: from)) }
        if let to { items.append(URLQueryItem(name: "to", value: to)) }
        if let limit { items.append(URLQueryItem(name: "limit", value: String(limit))) }
        return try await get(
            "/api/v1/repair-pricing/audit",
            query: items.isEmpty ? nil : items,
            as: [RepairPricingAuditRow].self
        )
    }

    /// Revert one custom price row to the server's tier default.
    func revertRepairPriceToTier(priceId: Int64) async throws -> RepairPricingRevertResult {
        try await post(
            "/api/v1/repair-pricing/revert/\(priceId)",
            body: EmptyRepairPricingBody(),
            as: RepairPricingRevertResult.self
        )
    }

    /// Refresh supplier-cost/profit metadata from the server catalog. Passing
    /// `autoMargin: true` asks the server to run its capped auto-margin pass
    /// after recomputing costs.
    func recomputeRepairPricingProfits(
        priceIds: [Int64]? = nil,
        autoMargin: Bool = false
    ) async throws -> RepairPricingProfitRecomputeResponse {
        try await post(
            "/api/v1/repair-pricing/recompute-profits",
            body: RepairPricingProfitRecomputeRequest(priceIds: priceIds, autoMargin: autoMargin),
            as: RepairPricingProfitRecomputeResponse.self
        )
    }
}
