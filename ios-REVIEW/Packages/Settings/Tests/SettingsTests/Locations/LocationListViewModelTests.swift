import Testing
import Foundation
@testable import Settings

// MARK: - Helpers

private func makeLoc(id: String, name: String = "Loc", isPrimary: Bool = false, active: Bool = true) -> Location {
    Location(id: id, name: name, addressLine1: "1 Main",
             city: "City", region: "ST", postal: "00000",
             country: "US", phone: "555", timezone: "UTC",
             active: active, isPrimary: isPrimary)
}

private final class StubRepo: LocationRepository, @unchecked Sendable {
    var locations: [Location]
    var shouldThrow: Bool = false

    init(locations: [Location] = []) { self.locations = locations }

    private func maybeThrow() throws {
        if shouldThrow { throw URLError(.badServerResponse) }
    }

    func fetchLocations() async throws -> [Location] { try maybeThrow(); return locations }
    func fetchLocation(id: String) async throws -> Location { try maybeThrow(); return locations[0] }
    func createLocation(_ request: CreateLocationRequest) async throws -> Location { try maybeThrow(); return locations[0] }
    func updateLocation(id: String, request: UpdateLocationRequest) async throws -> Location { try maybeThrow(); return locations[0] }
    func deleteLocation(id: String) async throws { try maybeThrow() }
    func setPrimary(id: String) async throws -> Location {
        try maybeThrow()
        return Location(id: id, name: "Primary", addressLine1: "1 P", city: "C", region: "S",
                        postal: "0", country: "US", phone: "5", timezone: "UTC", isPrimary: true)
    }
    func setActive(id: String, active: Bool) async throws -> Location {
        try maybeThrow()
        return Location(id: id, name: "X", addressLine1: "1 X", city: "C", region: "S",
                        postal: "0", country: "US", phone: "5", timezone: "UTC", active: active)
    }
    func fetchInventoryBalances(locationId: String?) async throws -> [LocationInventoryBalance] { try maybeThrow(); return [] }
    func fetchTransfers(locationId: String?) async throws -> [LocationTransferRequest] { try maybeThrow(); return [] }
    func createTransfer(_ request: CreateTransferRequest) async throws -> LocationTransferRequest {
        try maybeThrow()
        return LocationTransferRequest(id: "t", fromLocationId: request.fromLocationId,
                                       toLocationId: request.toLocationId, items: request.items)
    }
    func updateTransferStatus(id: String, status: String) async throws -> LocationTransferRequest {
        try maybeThrow()
        return LocationTransferRequest(id: id, fromLocationId: "a", toLocationId: "b", items: [], status: status)
    }
    func fetchLocationAccess(employeeId: String) async throws -> [LocationAccessEntry] { try maybeThrow(); return [] }
    func updateLocationAccess(employeeId: String, entries: [LocationAccessEntry]) async throws -> [LocationAccessEntry] {
        try maybeThrow(); return entries
    }
}

// MARK: - Tests

@Suite("LocationListViewModel")
@MainActor
struct LocationListViewModelTests {

    @Test("load transitions from idle → loading → loaded")
    func loadTransitions() async {
        let repo = StubRepo(locations: [makeLoc(id: "1")])
        let vm = LocationListViewModel(repo: repo)
        #expect(vm.loadState == .idle)
        await vm.load()
        #expect(vm.loadState == .loaded)
        #expect(vm.locations.count == 1)
    }

    @Test("load sets error state when repo throws")
    func loadError() async {
        let repo = StubRepo()
        repo.shouldThrow = true
        let vm = LocationListViewModel(repo: repo)
        await vm.load()
        if case .error = vm.loadState {} else {
            Issue.record("Expected error state")
        }
    }

    @Test("setPrimary marks location isPrimary and clears others")
    func setPrimary() async {
        let repo = StubRepo(locations: [makeLoc(id: "1"), makeLoc(id: "2")])
        let vm = LocationListViewModel(repo: repo)
        await vm.load()
        await vm.setPrimary(id: "1")
        let primary = vm.locations.first(where: { $0.id == "1" })
        #expect(primary?.isPrimary == true)
        let other = vm.locations.first(where: { $0.id == "2" })
        #expect(other?.isPrimary == false)
    }

    @Test("setActive updates active flag on matching location")
    func setActive() async {
        let repo = StubRepo(locations: [makeLoc(id: "a", active: true)])
        let vm = LocationListViewModel(repo: repo)
        await vm.load()
        await vm.setActive(id: "a", active: false)
        #expect(vm.locations.first(where: { $0.id == "a" })?.active == false)
    }

    @Test("delete removes location from list")
    func delete() async {
        let repo = StubRepo(locations: [makeLoc(id: "del"), makeLoc(id: "keep")])
        let vm = LocationListViewModel(repo: repo)
        await vm.load()
        await vm.delete(id: "del")
        #expect(vm.locations.allSatisfy { $0.id != "del" })
        #expect(vm.locations.count == 1)
    }

    @Test("setPrimary sets error state when repo throws")
    func setPrimaryError() async {
        let repo = StubRepo(locations: [makeLoc(id: "e")])
        let vm = LocationListViewModel(repo: repo)
        await vm.load()
        repo.shouldThrow = true
        await vm.setPrimary(id: "e")
        if case .error = vm.loadState {} else {
            Issue.record("Expected error state after repo throw")
        }
    }

    @Test("sortedLocations returns locations sorted by name")
    func sortedByName() async {
        let repo = StubRepo(locations: [makeLoc(id: "z", name: "Zoo"), makeLoc(id: "a", name: "Alpha")])
        let vm = LocationListViewModel(repo: repo)
        await vm.load()
        let sorted = vm.sortedLocations
        #expect(sorted.first?.name == "Alpha")
        #expect(sorted.last?.name == "Zoo")
    }
}
