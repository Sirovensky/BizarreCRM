import Foundation
import Networking

// MARK: - §43 Bulk Edit — API Wrappers

/// Server routes consumed by the Bulk Edit feature.
///
/// Existing routes (all under `/api/v1/repair-pricing`):
///
///   GET  /adjustments            → `{ success, data: { flat, pct } }`
///   PUT  /adjustments            → `{ success, data: { flat, pct } }`
///       body: { flat?, pct?, confirm_large_adjustment?: Bool }
///   GET  /prices                 → `{ success, data: [RepairPriceRow] }`
///   PUT  /prices/:id             → `{ success, data: RepairPriceRow }`
///       body: { labor_price?, default_grade?, is_active? }
///   POST /services               → `{ success, data: RepairServiceRow }`
///       body: { name, slug, category?, description?, is_active?, sort_order? }
///
/// No new routes are invented — all DTOs match the existing server shapes.

// MARK: - DTOs

/// A row from `repair_prices` returned by `GET /repair-pricing/prices`.
public struct RepairPriceRow: Decodable, Sendable, Identifiable, Equatable {
    public let id: Int64
    public let deviceModelId: Int64
    public let repairServiceId: Int64
    public let deviceModelName: String?
    public let manufacturerName: String?
    public let repairServiceName: String?
    public let repairServiceSlug: String?
    public let serviceCategory: String?
    /// Labor price in dollars (server stores as a float).
    public let laborPrice: Double
    public let defaultGrade: String
    public let isActive: Int
    public let gradeCount: Int

    public init(
        id: Int64,
        deviceModelId: Int64,
        repairServiceId: Int64,
        deviceModelName: String? = nil,
        manufacturerName: String? = nil,
        repairServiceName: String? = nil,
        repairServiceSlug: String? = nil,
        serviceCategory: String? = nil,
        laborPrice: Double = 0,
        defaultGrade: String = "aftermarket",
        isActive: Int = 1,
        gradeCount: Int = 0
    ) {
        self.id = id
        self.deviceModelId = deviceModelId
        self.repairServiceId = repairServiceId
        self.deviceModelName = deviceModelName
        self.manufacturerName = manufacturerName
        self.repairServiceName = repairServiceName
        self.repairServiceSlug = repairServiceSlug
        self.serviceCategory = serviceCategory
        self.laborPrice = laborPrice
        self.defaultGrade = defaultGrade
        self.isActive = isActive
        self.gradeCount = gradeCount
    }

    enum CodingKeys: String, CodingKey {
        case id
        case deviceModelId      = "device_model_id"
        case repairServiceId    = "repair_service_id"
        case deviceModelName    = "device_model_name"
        case manufacturerName   = "manufacturer_name"
        case repairServiceName  = "repair_service_name"
        case repairServiceSlug  = "repair_service_slug"
        case serviceCategory    = "service_category"
        case laborPrice         = "labor_price"
        case defaultGrade       = "default_grade"
        case isActive           = "is_active"
        case gradeCount         = "grade_count"
    }
}

/// Body for `PUT /repair-pricing/prices/:id`.
struct UpdateRepairPriceBody: Encodable, Sendable {
    let laborPrice: Double?
    let defaultGrade: String?
    let isActive: Int?

    enum CodingKeys: String, CodingKey {
        case laborPrice  = "labor_price"
        case defaultGrade = "default_grade"
        case isActive    = "is_active"
    }
}

/// Body for `PUT /repair-pricing/adjustments`.
struct UpdateGlobalAdjustmentsBody: Encodable, Sendable {
    let flat: Double?
    let pct: Double?
    /// Required by the server when |pct| > 20.
    let confirmLargeAdjustment: Bool?

    enum CodingKeys: String, CodingKey {
        case flat, pct
        case confirmLargeAdjustment = "confirm_large_adjustment"
    }
}

/// Body for `POST /repair-pricing/services` (used by ServicePresetImport).
struct CreateRepairServiceBody: Encodable, Sendable {
    let name: String
    let slug: String
    let category: String?
    let description: String?
    let isActive: Int
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case name, slug, category, description
        case isActive   = "is_active"
        case sortOrder  = "sort_order"
    }
}

/// A row from `repair_services` returned by POST /repair-pricing/services.
public struct RepairServiceRow: Decodable, Sendable, Identifiable, Equatable {
    public let id: Int64
    public let name: String
    public let slug: String
    public let category: String?
    public let description: String?
    public let isActive: Int
    public let sortOrder: Int

    public init(
        id: Int64,
        name: String,
        slug: String,
        category: String? = nil,
        description: String? = nil,
        isActive: Int = 1,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.category = category
        self.description = description
        self.isActive = isActive
        self.sortOrder = sortOrder
    }

    enum CodingKeys: String, CodingKey {
        case id, name, slug, category, description
        case isActive   = "is_active"
        case sortOrder  = "sort_order"
    }
}

// MARK: - APIClient extensions

public extension APIClient {

    /// Fetch all repair price rows (optionally filtered).
    ///
    /// Maps to `GET /api/v1/repair-pricing/prices`.
    func listRepairPrices(
        deviceModelId: Int64? = nil,
        repairServiceId: Int64? = nil,
        category: String? = nil
    ) async throws -> [RepairPriceRow] {
        var query: [URLQueryItem] = []
        if let v = deviceModelId  { query.append(URLQueryItem(name: "device_model_id",   value: String(v))) }
        if let v = repairServiceId { query.append(URLQueryItem(name: "repair_service_id", value: String(v))) }
        if let v = category        { query.append(URLQueryItem(name: "category",          value: v)) }
        return try await get(
            "/api/v1/repair-pricing/prices",
            query: query.isEmpty ? nil : query,
            as: [RepairPriceRow].self
        )
    }

    /// Update a single repair price row's labor price.
    ///
    /// Maps to `PUT /api/v1/repair-pricing/prices/:id`.
    func updateRepairPrice(id: Int64, laborPrice: Double) async throws -> RepairPriceRow {
        let body = UpdateRepairPriceBody(laborPrice: laborPrice, defaultGrade: nil, isActive: nil)
        return try await put(
            "/api/v1/repair-pricing/prices/\(id)",
            body: body,
            as: RepairPriceRow.self
        )
    }

    /// Update global pricing adjustments.
    ///
    /// Maps to `PUT /api/v1/repair-pricing/adjustments`.
    /// Pass `confirmLargeAdjustment: true` when `|pct| > 20` (server requires this).
    func updateGlobalAdjustments(
        flat: Double? = nil,
        pct: Double? = nil,
        confirmLargeAdjustment: Bool = false
    ) async throws -> RepairPricingAdjustments {
        let body = UpdateGlobalAdjustmentsBody(
            flat: flat,
            pct: pct,
            confirmLargeAdjustment: confirmLargeAdjustment ? true : nil
        )
        return try await put(
            "/api/v1/repair-pricing/adjustments",
            body: body,
            as: RepairPricingAdjustments.self
        )
    }

    /// Create a new repair service.
    ///
    /// Maps to `POST /api/v1/repair-pricing/services`.
    func createRepairService(
        name: String,
        slug: String,
        category: String? = nil,
        description: String? = nil,
        isActive: Int = 1,
        sortOrder: Int = 0
    ) async throws -> RepairServiceRow {
        let body = CreateRepairServiceBody(
            name: name,
            slug: slug,
            category: category,
            description: description,
            isActive: isActive,
            sortOrder: sortOrder
        )
        return try await post(
            "/api/v1/repair-pricing/services",
            body: body,
            as: RepairServiceRow.self
        )
    }
}
