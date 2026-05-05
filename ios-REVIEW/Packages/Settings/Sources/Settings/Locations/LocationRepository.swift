import Foundation
import Networking

// MARK: - §60 LocationRepository protocol

public protocol LocationRepository: Sendable {
    func fetchLocations() async throws -> [Location]
    func fetchLocation(id: String) async throws -> Location
    func createLocation(_ request: CreateLocationRequest) async throws -> Location
    func updateLocation(id: String, request: UpdateLocationRequest) async throws -> Location
    func deleteLocation(id: String) async throws
    func setPrimary(id: String) async throws -> Location
    func setActive(id: String, active: Bool) async throws -> Location

    func fetchInventoryBalances(locationId: String?) async throws -> [LocationInventoryBalance]
    func fetchTransfers(locationId: String?) async throws -> [LocationTransferRequest]
    func createTransfer(_ request: CreateTransferRequest) async throws -> LocationTransferRequest
    func updateTransferStatus(id: String, status: String) async throws -> LocationTransferRequest

    func fetchLocationAccess(employeeId: String) async throws -> [LocationAccessEntry]
    func updateLocationAccess(employeeId: String, entries: [LocationAccessEntry]) async throws -> [LocationAccessEntry]
}

// MARK: - Live implementation

public struct LiveLocationRepository: LocationRepository {
    private let api: any APIClient

    public init(api: any APIClient) {
        self.api = api
    }

    public func fetchLocations() async throws -> [Location] {
        try await api.listLocations()
    }

    public func fetchLocation(id: String) async throws -> Location {
        try await api.fetchLocation(id: id)
    }

    public func createLocation(_ request: CreateLocationRequest) async throws -> Location {
        try await api.createLocation(request)
    }

    public func updateLocation(id: String, request: UpdateLocationRequest) async throws -> Location {
        try await api.updateLocation(id: id, body: request)
    }

    public func deleteLocation(id: String) async throws {
        try await api.deleteLocation(id: id)
    }

    public func setPrimary(id: String) async throws -> Location {
        try await api.setPrimaryLocation(id: id)
    }

    public func setActive(id: String, active: Bool) async throws -> Location {
        try await api.setLocationActive(id: id, active: active)
    }

    public func fetchInventoryBalances(locationId: String?) async throws -> [LocationInventoryBalance] {
        try await api.locationInventoryBalances(locationId: locationId)
    }

    public func fetchTransfers(locationId: String?) async throws -> [LocationTransferRequest] {
        try await api.listTransfers(locationId: locationId)
    }

    public func createTransfer(_ request: CreateTransferRequest) async throws -> LocationTransferRequest {
        try await api.createTransfer(request)
    }

    public func updateTransferStatus(id: String, status: String) async throws -> LocationTransferRequest {
        try await api.updateTransferStatus(id: id, status: status)
    }

    public func fetchLocationAccess(employeeId: String) async throws -> [LocationAccessEntry] {
        try await api.locationAccessForEmployee(employeeId: employeeId)
    }

    public func updateLocationAccess(employeeId: String, entries: [LocationAccessEntry]) async throws -> [LocationAccessEntry] {
        try await api.updateLocationAccess(
            employeeId: employeeId,
            body: UpdateLocationAccessRequest(entries: entries)
        )
    }
}
