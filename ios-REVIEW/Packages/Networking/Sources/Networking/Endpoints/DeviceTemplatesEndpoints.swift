import Foundation

/// §43 — Device Templates / Repair-Pricing Catalog DTOs + APIClient wrappers.
///
/// Server routes:
///   • `GET /api/v1/device-templates`      → `{ success, data: [DeviceTemplate] }`
///   • `GET /api/v1/device-templates/:id`  → `{ success, data: DeviceTemplate }`
///   • `GET /api/v1/repair-pricing/services` → `{ success, data: [RepairService] }`
///
/// All server fields use snake_case; CodingKeys map them to Swift camelCase.
/// `device_model_templates` DB columns: id, name, device_category, device_model,
/// fault, est_labor_minutes, est_labor_cost, suggested_price, diagnostic_checklist_json,
/// parts_json, warranty_days, is_active, sort_order, created_at, updated_at.

// MARK: - DTOs

/// A device model repair template. `family` maps from `device_category`,
/// `model` from `device_model`, `defaultServicePriceCents` from `suggested_price`.
/// Nested `services` is only populated on the detail endpoint.
public struct DeviceTemplate: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    /// Human-readable name, e.g. "iPhone 15 Pro Screen Replacement"
    public let name: String
    /// Device family / category, e.g. "Apple", "Samsung", "Google"
    public let family: String?
    /// Specific model, e.g. "iPhone 15 Pro"
    public let model: String?
    /// Optional colour variant descriptor
    public let color: String?
    /// URL for thumbnail image (not in current DB schema — reserved for future)
    public let thumbnailUrl: String?
    /// IMEI validation regex pattern, if any
    public let imeiPattern: String?
    /// Diagnostic / intake condition checklist items
    public let conditions: [String]
    /// Repair services attached to this template (only on detail endpoint)
    public let services: [RepairService]?
    /// Labour estimate in minutes
    public let estimatedMinutes: Int?
    /// Suggested price in cents
    public let defaultPriceCents: Int?
    /// Warranty in days
    public let warrantyDays: Int

    public init(
        id: Int64,
        name: String,
        family: String?,
        model: String?,
        color: String? = nil,
        thumbnailUrl: String? = nil,
        imeiPattern: String? = nil,
        conditions: [String] = [],
        services: [RepairService]? = nil,
        estimatedMinutes: Int? = nil,
        defaultPriceCents: Int? = nil,
        warrantyDays: Int = 30
    ) {
        self.id = id
        self.name = name
        self.family = family
        self.model = model
        self.color = color
        self.thumbnailUrl = thumbnailUrl
        self.imeiPattern = imeiPattern
        self.conditions = conditions
        self.services = services
        self.estimatedMinutes = estimatedMinutes
        self.defaultPriceCents = defaultPriceCents
        self.warrantyDays = warrantyDays
    }

    enum CodingKeys: String, CodingKey {
        case id, name, color, services
        case family            = "device_category"
        case model             = "device_model"
        case thumbnailUrl      = "thumbnail_url"
        case imeiPattern       = "imei_pattern"
        case conditions        = "diagnostic_checklist"
        case estimatedMinutes  = "est_labor_minutes"
        case defaultPriceCents = "suggested_price"
        case warrantyDays      = "warranty_days"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int64.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.family = try c.decodeIfPresent(String.self, forKey: .family)
        self.model = try c.decodeIfPresent(String.self, forKey: .model)
        self.color = try c.decodeIfPresent(String.self, forKey: .color)
        self.thumbnailUrl = try c.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        self.imeiPattern = try c.decodeIfPresent(String.self, forKey: .imeiPattern)
        // `diagnostic_checklist` on the server is an enriched array; the route
        // also injects the parsed array directly. Fall back to empty array.
        self.conditions = (try? c.decodeIfPresent([String].self, forKey: .conditions)) ?? []
        self.services = try c.decodeIfPresent([RepairService].self, forKey: .services)
        self.estimatedMinutes = try c.decodeIfPresent(Int.self, forKey: .estimatedMinutes)
        self.defaultPriceCents = try c.decodeIfPresent(Int.self, forKey: .defaultPriceCents)
        self.warrantyDays = (try? c.decodeIfPresent(Int.self, forKey: .warrantyDays)) ?? 30
    }
}

/// A catalogued repair service. Used both standalone (from
/// `/api/v1/repair-pricing/services`) and nested inside `DeviceTemplate`.
public struct RepairService: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    /// Device family this service applies to (optional — may be cross-family)
    public let family: String?
    /// Device model this service applies to (optional)
    public let model: String?
    /// Human-readable service name, e.g. "Screen Replacement"
    public let serviceName: String
    /// Default price in cents
    public let defaultPriceCents: Int
    /// Part SKU for inventory lookup
    public let partSku: String?
    /// Estimated duration in minutes
    public let estimatedMinutes: Int?

    public init(
        id: Int64,
        family: String? = nil,
        model: String? = nil,
        serviceName: String,
        defaultPriceCents: Int,
        partSku: String? = nil,
        estimatedMinutes: Int? = nil
    ) {
        self.id = id
        self.family = family
        self.model = model
        self.serviceName = serviceName
        self.defaultPriceCents = defaultPriceCents
        self.partSku = partSku
        self.estimatedMinutes = estimatedMinutes
    }

    enum CodingKeys: String, CodingKey {
        case id, family, model
        case serviceName       = "service_name"
        case defaultPriceCents = "default_price_cents"
        case partSku           = "part_sku"
        case estimatedMinutes  = "estimated_minutes"
    }
}

// MARK: - APIClient wrappers

public extension APIClient {
    /// List all active device templates. Optionally filter by category / family
    /// (passed as `category` query param matching `device_category` column).
    func listDeviceTemplates(family: String? = nil) async throws -> [DeviceTemplate] {
        var query: [URLQueryItem] = []
        if let family, !family.isEmpty {
            query.append(URLQueryItem(name: "category", value: family))
        }
        return try await get(
            "/api/v1/device-templates",
            query: query.isEmpty ? nil : query,
            as: [DeviceTemplate].self
        )
    }

    /// Fetch a single device template by id — includes enriched parts +
    /// the diagnostic checklist.
    func getDeviceTemplate(id: Int64) async throws -> DeviceTemplate {
        try await get("/api/v1/device-templates/\(id)", as: DeviceTemplate.self)
    }

    /// List repair services from the pricing catalog.
    /// - Parameters:
    ///   - family: Optional device category filter (maps to server `category` param).
    ///   - model: Not currently supported by server — reserved for future use.
    ///   - pageSize: Soft client-side cap; server returns all rows, we truncate.
    func listRepairServices(
        family: String? = nil,
        model: String? = nil,
        pageSize: Int = 100
    ) async throws -> [RepairService] {
        var query: [URLQueryItem] = []
        if let family, !family.isEmpty {
            query.append(URLQueryItem(name: "category", value: family))
        }
        let rows = try await get(
            "/api/v1/repair-pricing/services",
            query: query.isEmpty ? nil : query,
            as: [RepairService].self
        )
        return Array(rows.prefix(pageSize))
    }
}
