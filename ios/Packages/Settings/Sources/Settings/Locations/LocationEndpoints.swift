import Foundation
import Networking

// MARK: - §60 Location API endpoints

/// All location-domain endpoints live here per the additive rule
/// (one file per domain, `APIClient+Locations.swift` naming preserved
/// but placed inside the owning package to avoid cross-package edits).
public extension APIClient {

    // MARK: Location CRUD

    func listLocations() async throws -> [Location] {
        try await get("/api/v1/locations", as: [Location].self)
    }

    func fetchLocation(id: String) async throws -> Location {
        try await get("/api/v1/locations/\(id)", as: Location.self)
    }

    func createLocation(_ body: CreateLocationRequest) async throws -> Location {
        try await post("/api/v1/locations", body: body, as: Location.self)
    }

    func updateLocation(id: String, body: UpdateLocationRequest) async throws -> Location {
        try await patch("/api/v1/locations/\(id)", body: body, as: Location.self)
    }

    func deleteLocation(id: String) async throws {
        try await delete("/api/v1/locations/\(id)")
    }

    func setPrimaryLocation(id: String) async throws -> Location {
        try await patch("/api/v1/locations/\(id)/set-primary",
                        body: EmptyBody(),
                        as: Location.self)
    }

    func setLocationActive(id: String, active: Bool) async throws -> Location {
        try await patch("/api/v1/locations/\(id)/active",
                        body: SetActiveRequest(active: active),
                        as: Location.self)
    }

    // MARK: Inventory balance

    func locationInventoryBalances(locationId: String? = nil) async throws -> [LocationInventoryBalance] {
        var query: [URLQueryItem] = []
        if let locationId {
            query.append(URLQueryItem(name: "location_id", value: locationId))
        }
        return try await get("/api/v1/inventory/location-balances",
                             query: query.isEmpty ? nil : query,
                             as: [LocationInventoryBalance].self)
    }

    // MARK: Transfers

    func listTransfers(locationId: String? = nil) async throws -> [LocationTransferRequest] {
        var query: [URLQueryItem] = []
        if let locationId {
            query.append(URLQueryItem(name: "location_id", value: locationId))
        }
        return try await get("/api/v1/inventory/transfers",
                             query: query.isEmpty ? nil : query,
                             as: [LocationTransferRequest].self)
    }

    func createTransfer(_ body: CreateTransferRequest) async throws -> LocationTransferRequest {
        try await post("/api/v1/inventory/transfers",
                       body: body,
                       as: LocationTransferRequest.self)
    }

    func updateTransferStatus(id: String, status: String) async throws -> LocationTransferRequest {
        try await patch("/api/v1/inventory/transfers/\(id)/status",
                        body: UpdateStatusRequest(status: status),
                        as: LocationTransferRequest.self)
    }

    // MARK: Employee location access

    func locationAccessForEmployee(employeeId: String) async throws -> [LocationAccessEntry] {
        try await get("/api/v1/employees/\(employeeId)/location-access",
                      as: [LocationAccessEntry].self)
    }

    func updateLocationAccess(employeeId: String, body: UpdateLocationAccessRequest) async throws -> [LocationAccessEntry] {
        try await patch("/api/v1/employees/\(employeeId)/location-access",
                        body: body,
                        as: [LocationAccessEntry].self)
    }
}

// MARK: - Request DTOs

public struct CreateLocationRequest: Encodable, Sendable {
    public let name: String
    public let addressLine1: String
    public let addressLine2: String?
    public let city: String
    public let region: String
    public let postal: String
    public let country: String
    public let phone: String
    public let timezone: String
    public let taxRateId: String?

    public init(
        name: String,
        addressLine1: String,
        addressLine2: String? = nil,
        city: String,
        region: String,
        postal: String,
        country: String,
        phone: String,
        timezone: String,
        taxRateId: String? = nil
    ) {
        self.name = name
        self.addressLine1 = addressLine1
        self.addressLine2 = addressLine2
        self.city = city
        self.region = region
        self.postal = postal
        self.country = country
        self.phone = phone
        self.timezone = timezone
        self.taxRateId = taxRateId
    }
}

public struct UpdateLocationRequest: Encodable, Sendable {
    public let name: String?
    public let addressLine1: String?
    public let addressLine2: String?
    public let city: String?
    public let region: String?
    public let postal: String?
    public let country: String?
    public let phone: String?
    public let timezone: String?
    public let taxRateId: String?
    public let openingHours: [LocationBusinessDay]?

    public init(
        name: String? = nil,
        addressLine1: String? = nil,
        addressLine2: String? = nil,
        city: String? = nil,
        region: String? = nil,
        postal: String? = nil,
        country: String? = nil,
        phone: String? = nil,
        timezone: String? = nil,
        taxRateId: String? = nil,
        openingHours: [LocationBusinessDay]? = nil
    ) {
        self.name = name
        self.addressLine1 = addressLine1
        self.addressLine2 = addressLine2
        self.city = city
        self.region = region
        self.postal = postal
        self.country = country
        self.phone = phone
        self.timezone = timezone
        self.taxRateId = taxRateId
        self.openingHours = openingHours
    }
}

public struct CreateTransferRequest: Encodable, Sendable {
    public let fromLocationId: String
    public let toLocationId: String
    public let items: [TransferItem]

    public init(fromLocationId: String, toLocationId: String, items: [TransferItem]) {
        self.fromLocationId = fromLocationId
        self.toLocationId = toLocationId
        self.items = items
    }
}

public struct UpdateLocationAccessRequest: Encodable, Sendable {
    public let entries: [LocationAccessEntry]

    public init(entries: [LocationAccessEntry]) {
        self.entries = entries
    }
}

private struct SetActiveRequest: Encodable, Sendable {
    let active: Bool
}

private struct UpdateStatusRequest: Encodable, Sendable {
    let status: String
}

private struct EmptyBody: Encodable, Sendable {}
