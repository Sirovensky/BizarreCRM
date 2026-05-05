import Foundation

// §4.3 — Device catalog picker endpoints.
//
// The device catalog is a separate server-side catalog distinct from the
// tenant's own device templates (§43). These routes surface the master
// device model database used to auto-populate manufacturer/model during
// ticket intake.
//
// Server routes (packages/server/src/routes/catalog.routes.ts):
//   GET /api/v1/catalog/manufacturers  → { manufacturers: [String] }
//   GET /api/v1/catalog/devices?keyword=<q>&manufacturer=<m>&limit=<n>
//       → { devices: [CatalogDevice] }

// MARK: - DTOs

/// A manufacturer entry from the global device catalog.
public struct CatalogManufacturer: Decodable, Sendable, Identifiable, Hashable {
    /// Using name as id since the server returns plain strings.
    public var id: String { name }
    public let name: String

    /// Decode from either a plain `String` (server returns string array) or
    /// an object with a `name` key, whichever the server currently uses.
    public init(from decoder: Decoder) throws {
        if let name = try? String(from: decoder) {
            self.name = name
        } else {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.name = try c.decode(String.self, forKey: .name)
        }
    }

    public init(name: String) { self.name = name }

    private enum CodingKeys: String, CodingKey { case name }
}

private struct _ManufacturersResponse: Decodable, Sendable {
    let manufacturers: [CatalogManufacturer]
}

/// A device from the global catalog. Returned by
/// `GET /api/v1/catalog/devices?keyword=&manufacturer=`.
public struct CatalogDevice: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let manufacturer: String?
    public let model: String
    public let family: String?
    /// Year the model was released (optional).
    public let releaseYear: Int?
    /// Suggested IMEI regex pattern for this device family, if any.
    public let imeiPattern: String?

    public var displayName: String {
        if let mfr = manufacturer, !mfr.isEmpty { return "\(mfr) \(model)" }
        return model
    }

    enum CodingKeys: String, CodingKey {
        case id, model, family
        case manufacturer
        case releaseYear = "release_year"
        case imeiPattern = "imei_pattern"
    }
}

private struct _CatalogDevicesResponse: Decodable, Sendable {
    let devices: [CatalogDevice]
}

// MARK: - APIClient wrappers

public extension APIClient {
    /// `GET /api/v1/catalog/manufacturers`
    ///
    /// Returns the list of device manufacturers known to the catalog.
    /// Used to drive the first level of the hierarchical device picker.
    func listCatalogManufacturers() async throws -> [CatalogManufacturer] {
        try await get(
            "/api/v1/catalog/manufacturers",
            as: _ManufacturersResponse.self
        ).manufacturers
    }

    /// `GET /api/v1/catalog/devices?keyword=<q>&manufacturer=<m>&limit=<n>`
    ///
    /// Returns devices matching the keyword / manufacturer filter.
    /// - Parameters:
    ///   - keyword: Free-text search across model names.
    ///   - manufacturer: Optional manufacturer filter.
    ///   - limit: Page size (default 50).
    func searchCatalogDevices(
        keyword: String? = nil,
        manufacturer: String? = nil,
        limit: Int = 50
    ) async throws -> [CatalogDevice] {
        var query: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let k = keyword, !k.isEmpty {
            query.append(URLQueryItem(name: "keyword", value: k))
        }
        if let m = manufacturer, !m.isEmpty {
            query.append(URLQueryItem(name: "manufacturer", value: m))
        }
        return try await get(
            "/api/v1/catalog/devices",
            query: query,
            as: _CatalogDevicesResponse.self
        ).devices
    }
}
