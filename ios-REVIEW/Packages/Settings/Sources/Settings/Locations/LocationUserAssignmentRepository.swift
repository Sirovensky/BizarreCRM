import Foundation
import Networking

// MARK: - §60.4 / §60.5 User-location assignment extensions

/// Extends LocationRepository with the user-location assignment methods
/// introduced in §60 Phase 4 (migration 141).
///
/// Server endpoints:
///   GET  /api/v1/locations/me/default-location
///   GET  /api/v1/locations/users/:userId/locations
///   POST /api/v1/locations/users/:userId/locations/:locationId
///   DELETE /api/v1/locations/users/:userId/locations/:locationId
public protocol LocationUserAssignmentRepository: LocationRepository {
    /// Returns the current user's default location (or nil if none is set).
    func fetchDefaultLocation() async throws -> Location?

    /// Returns all locations assigned to the given user.
    func fetchUserLocations(userId: String) async throws -> [UserLocationAssignment]

    /// Upsert-assigns `locationId` to `userId`.
    /// When `isPrimary` is true the server clears any existing primary for the user first.
    @discardableResult
    func assignUserLocation(userId: String, locationId: String, isPrimary: Bool) async throws -> UserLocationRow

    /// Removes the location assignment.  Blocked server-side if it would
    /// leave the user with zero assignments.
    func removeUserLocation(userId: String, locationId: String) async throws
}

// MARK: - Model

/// A location as returned when listing a user's assigned locations,
/// enriched with the assignment metadata from `user_locations`.
public struct UserLocationAssignment: Codable, Sendable, Identifiable {
    public var id: String { "\(userId)-\(location.id)" }
    public let userId: String
    public let location: Location
    public let isPrimary: Bool
    public let roleAtLocation: String?
    public let assignedAt: String

    public init(
        userId: String,
        location: Location,
        isPrimary: Bool,
        roleAtLocation: String?,
        assignedAt: String
    ) {
        self.userId = userId
        self.location = location
        self.isPrimary = isPrimary
        self.roleAtLocation = roleAtLocation
        self.assignedAt = assignedAt
    }
}

// MARK: - Live implementation

public struct LiveLocationUserAssignmentRepository: LocationUserAssignmentRepository {
    private let inner: LiveLocationRepository
    private let api: any APIClient

    public init(api: any APIClient) {
        self.inner = LiveLocationRepository(api: api)
        self.api = api
    }

    // Delegate all existing LocationRepository requirements to the inner impl
    public func fetchLocations() async throws -> [Location] { try await inner.fetchLocations() }
    public func fetchLocation(id: String) async throws -> Location { try await inner.fetchLocation(id: id) }
    public func createLocation(_ request: CreateLocationRequest) async throws -> Location { try await inner.createLocation(request) }
    public func updateLocation(id: String, request: UpdateLocationRequest) async throws -> Location { try await inner.updateLocation(id: id, request: request) }
    public func deleteLocation(id: String) async throws { try await inner.deleteLocation(id: id) }
    public func setPrimary(id: String) async throws -> Location { try await inner.setPrimary(id: id) }
    public func setActive(id: String, active: Bool) async throws -> Location { try await inner.setActive(id: id, active: active) }
    public func fetchInventoryBalances(locationId: String?) async throws -> [LocationInventoryBalance] { try await inner.fetchInventoryBalances(locationId: locationId) }
    public func fetchTransfers(locationId: String?) async throws -> [LocationTransferRequest] { try await inner.fetchTransfers(locationId: locationId) }
    public func createTransfer(_ request: CreateTransferRequest) async throws -> LocationTransferRequest { try await inner.createTransfer(request) }
    public func updateTransferStatus(id: String, status: String) async throws -> LocationTransferRequest { try await inner.updateTransferStatus(id: id, status: status) }
    public func fetchLocationAccess(employeeId: String) async throws -> [LocationAccessEntry] { try await inner.fetchLocationAccess(employeeId: employeeId) }
    public func updateLocationAccess(employeeId: String, entries: [LocationAccessEntry]) async throws -> [LocationAccessEntry] { try await inner.updateLocationAccess(employeeId: employeeId, entries: entries) }

    // New methods
    public func fetchDefaultLocation() async throws -> Location? {
        try await api.fetchMyDefaultLocation()
    }

    public func fetchUserLocations(userId: String) async throws -> [UserLocationAssignment] {
        try await api.fetchUserLocations(userId: userId)
    }

    @discardableResult
    public func assignUserLocation(userId: String, locationId: String, isPrimary: Bool) async throws -> UserLocationRow {
        try await api.assignUserLocation(userId: userId, locationId: locationId, isPrimary: isPrimary)
    }

    public func removeUserLocation(userId: String, locationId: String) async throws {
        try await api.removeUserLocation(userId: userId, locationId: locationId)
    }
}

// MARK: - New APIClient endpoints

public extension APIClient {

    /// GET /api/v1/locations/me/default-location
    func fetchMyDefaultLocation() async throws -> Location? {
        // Envelope: { success: true, data: Location? }
        // Server returns data: null when no default is set
        try await get("/api/v1/locations/me/default-location", as: Location?.self)
    }

    /// GET /api/v1/locations/users/:userId/locations
    func fetchUserLocations(userId: String) async throws -> [UserLocationAssignment] {
        try await get("/api/v1/locations/users/\(userId)/locations", as: [UserLocationAssignment].self)
    }

    /// POST /api/v1/locations/users/:userId/locations/:locationId
    /// Body: { is_primary: Bool }
    /// Returns the upserted `user_locations` row.
    @discardableResult
    func assignUserLocation(userId: String, locationId: String, isPrimary: Bool) async throws -> UserLocationRow {
        try await post(
            "/api/v1/locations/users/\(userId)/locations/\(locationId)",
            body: AssignLocationBody(isPrimary: isPrimary),
            as: UserLocationRow.self
        )
    }

    /// DELETE /api/v1/locations/users/:userId/locations/:locationId
    func removeUserLocation(userId: String, locationId: String) async throws {
        try await delete("/api/v1/locations/users/\(userId)/locations/\(locationId)")
    }
}

// MARK: - DTOs (private to this file)

private struct AssignLocationBody: Encodable, Sendable {
    let isPrimary: Bool

    enum CodingKeys: String, CodingKey {
        case isPrimary = "is_primary"
    }
}

/// Mirrors the `user_locations` row returned by
/// `POST /api/v1/locations/users/:userId/locations/:locationId`.
public struct UserLocationRow: Decodable, Sendable {
    public let userId: Int
    public let locationId: Int
    public let isPrimary: Bool
    public let roleAtLocation: String?
    public let assignedAt: String
}
