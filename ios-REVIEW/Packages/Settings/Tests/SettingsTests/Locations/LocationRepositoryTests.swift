import Testing
import Foundation
@testable import Settings

// MARK: - Stub

private final class StubLocationRepo: LocationRepository, @unchecked Sendable {

    // MARK: Configuration

    var stubbedLocations: [Location] = []
    var shouldThrow: Bool = false
    var lastCreatedRequest: CreateLocationRequest? = nil
    var lastUpdatedId: String? = nil
    var lastDeletedId: String? = nil
    var lastPrimaryId: String? = nil
    var lastActiveCall: (id: String, active: Bool)? = nil
    var lastTransferRequest: CreateTransferRequest? = nil
    var lastStatusUpdate: (id: String, status: String)? = nil
    var lastAccessUpdate: (employeeId: String, entries: [LocationAccessEntry])? = nil

    var stubbedBalances: [LocationInventoryBalance] = []
    var stubbedTransfers: [LocationTransferRequest] = []
    var stubbedAccess: [LocationAccessEntry] = []

    private func maybeThrow() throws {
        if shouldThrow { throw URLError(.badServerResponse) }
    }

    // MARK: Protocol

    func fetchLocations() async throws -> [Location] {
        try maybeThrow()
        return stubbedLocations
    }

    func fetchLocation(id: String) async throws -> Location {
        try maybeThrow()
        guard let loc = stubbedLocations.first(where: { $0.id == id }) else {
            throw URLError(.fileDoesNotExist)
        }
        return loc
    }

    func createLocation(_ request: CreateLocationRequest) async throws -> Location {
        try maybeThrow()
        lastCreatedRequest = request
        return Location(id: "new-id", name: request.name, addressLine1: request.addressLine1,
                        city: request.city, region: request.region, postal: request.postal,
                        country: request.country, phone: request.phone, timezone: request.timezone)
    }

    func updateLocation(id: String, request: UpdateLocationRequest) async throws -> Location {
        try maybeThrow()
        lastUpdatedId = id
        return stubbedLocations.first(where: { $0.id == id }) ?? makeLoc(id: id)
    }

    func deleteLocation(id: String) async throws {
        try maybeThrow()
        lastDeletedId = id
    }

    func setPrimary(id: String) async throws -> Location {
        try maybeThrow()
        lastPrimaryId = id
        return makeLoc(id: id, isPrimary: true)
    }

    func setActive(id: String, active: Bool) async throws -> Location {
        try maybeThrow()
        lastActiveCall = (id, active)
        return makeLoc(id: id, active: active)
    }

    func fetchInventoryBalances(locationId: String?) async throws -> [LocationInventoryBalance] {
        try maybeThrow()
        return stubbedBalances
    }

    func fetchTransfers(locationId: String?) async throws -> [LocationTransferRequest] {
        try maybeThrow()
        return stubbedTransfers
    }

    func createTransfer(_ request: CreateTransferRequest) async throws -> LocationTransferRequest {
        try maybeThrow()
        lastTransferRequest = request
        return LocationTransferRequest(
            id: "t-1",
            fromLocationId: request.fromLocationId,
            toLocationId: request.toLocationId,
            items: request.items
        )
    }

    func updateTransferStatus(id: String, status: String) async throws -> LocationTransferRequest {
        try maybeThrow()
        lastStatusUpdate = (id, status)
        return LocationTransferRequest(id: id, fromLocationId: "a", toLocationId: "b", items: [], status: status)
    }

    func fetchLocationAccess(employeeId: String) async throws -> [LocationAccessEntry] {
        try maybeThrow()
        return stubbedAccess
    }

    func updateLocationAccess(employeeId: String, entries: [LocationAccessEntry]) async throws -> [LocationAccessEntry] {
        try maybeThrow()
        lastAccessUpdate = (employeeId, entries)
        return entries
    }

    // MARK: Helpers

    private func makeLoc(id: String, isPrimary: Bool = false, active: Bool = true) -> Location {
        Location(id: id, name: "Test", addressLine1: "1 Main St",
                 city: "Testville", region: "TX", postal: "12345",
                 country: "US", phone: "555-0000", timezone: "UTC",
                 active: active, isPrimary: isPrimary)
    }
}

// MARK: - Tests

@Suite("LocationRepository — happy path")
@MainActor
struct LocationRepositoryHappyTests {

    @Test("fetchLocations returns stubbed list")
    func fetchLocations() async throws {
        let repo = StubLocationRepo()
        repo.stubbedLocations = [
            Location(id: "1", name: "A", addressLine1: "1 A", city: "City",
                     region: "ST", postal: "00000", country: "US",
                     phone: "555", timezone: "UTC")
        ]
        let result = try await repo.fetchLocations()
        #expect(result.count == 1)
        #expect(result[0].id == "1")
    }

    @Test("createLocation passes request through")
    func createLocation() async throws {
        let repo = StubLocationRepo()
        let req = CreateLocationRequest(name: "HQ", addressLine1: "1 HQ",
                                        city: "New York", region: "NY",
                                        postal: "10001", country: "US",
                                        phone: "212-000-0000", timezone: "America/New_York")
        let loc = try await repo.createLocation(req)
        #expect(loc.name == "HQ")
        #expect(repo.lastCreatedRequest?.name == "HQ")
    }

    @Test("deleteLocation records deleted id")
    func deleteLocation() async throws {
        let repo = StubLocationRepo()
        try await repo.deleteLocation(id: "del-1")
        #expect(repo.lastDeletedId == "del-1")
    }

    @Test("setPrimary marks location as primary")
    func setPrimary() async throws {
        let repo = StubLocationRepo()
        let loc = try await repo.setPrimary(id: "p-1")
        #expect(loc.isPrimary == true)
        #expect(repo.lastPrimaryId == "p-1")
    }

    @Test("setActive forwards active flag")
    func setActive() async throws {
        let repo = StubLocationRepo()
        let loc = try await repo.setActive(id: "a-1", active: false)
        #expect(loc.active == false)
        #expect(repo.lastActiveCall?.id == "a-1")
        #expect(repo.lastActiveCall?.active == false)
    }

    @Test("createTransfer records request")
    func createTransfer() async throws {
        let repo = StubLocationRepo()
        let req = CreateTransferRequest(
            fromLocationId: "loc-a", toLocationId: "loc-b",
            items: [TransferItem(sku: "SKU-1", quantity: 5)]
        )
        let transfer = try await repo.createTransfer(req)
        #expect(transfer.fromLocationId == "loc-a")
        #expect(transfer.toLocationId == "loc-b")
        #expect(repo.lastTransferRequest?.items.first?.sku == "SKU-1")
    }
}

@Suite("LocationRepository — error path")
@MainActor
struct LocationRepositoryErrorTests {

    @Test("fetchLocations throws when shouldThrow")
    func fetchLocationsThrows() async {
        let repo = StubLocationRepo()
        repo.shouldThrow = true
        do {
            _ = try await repo.fetchLocations()
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is URLError)
        }
    }

    @Test("createTransfer throws when shouldThrow")
    func createTransferThrows() async {
        let repo = StubLocationRepo()
        repo.shouldThrow = true
        do {
            _ = try await repo.createTransfer(
                CreateTransferRequest(fromLocationId: "a", toLocationId: "b", items: [])
            )
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is URLError)
        }
    }

    @Test("deleteLocation throws when shouldThrow")
    func deleteLocationThrows() async {
        let repo = StubLocationRepo()
        repo.shouldThrow = true
        do {
            try await repo.deleteLocation(id: "x")
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is URLError)
        }
    }
}
