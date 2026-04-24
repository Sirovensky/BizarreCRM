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
}
