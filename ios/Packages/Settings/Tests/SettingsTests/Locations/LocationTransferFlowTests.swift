import Testing
import Foundation
@testable import Settings

// MARK: - Transfer flow tests

private func makeTransfer(id: String, from: String = "A", to: String = "B", status: String = "requested") -> LocationTransferRequest {
    LocationTransferRequest(
        id: id, fromLocationId: from, toLocationId: to,
        items: [TransferItem(sku: "SKU-1", quantity: 2)],
        status: status
    )
}

private func makeLoc(id: String, name: String = "Loc") -> Location {
    Location(id: id, name: name, addressLine1: "1 Main", city: "City",
             region: "ST", postal: "00000", country: "US", phone: "555", timezone: "UTC")
}

private final class TransferStubRepo: LocationRepository, @unchecked Sendable {
    var transfers: [LocationTransferRequest] = []
    var shouldThrow: Bool = false
    var lastCreated: CreateTransferRequest? = nil

    private func maybeThrow() throws { if shouldThrow { throw URLError(.badServerResponse) } }

    func fetchLocations() async throws -> [Location] { [] }
    func fetchLocation(id: String) async throws -> Location { makeLoc(id: id) }
    func createLocation(_ r: CreateLocationRequest) async throws -> Location { makeLoc(id: "new") }
    func updateLocation(id: String, request: UpdateLocationRequest) async throws -> Location { makeLoc(id: id) }
    func deleteLocation(id: String) async throws {}
    func setPrimary(id: String) async throws -> Location { makeLoc(id: id) }
    func setActive(id: String, active: Bool) async throws -> Location { makeLoc(id: id) }
    func fetchInventoryBalances(locationId: String?) async throws -> [LocationInventoryBalance] { [] }
    func fetchLocationAccess(employeeId: String) async throws -> [LocationAccessEntry] { [] }
    func updateLocationAccess(employeeId: String, entries: [LocationAccessEntry]) async throws -> [LocationAccessEntry] { entries }

    func fetchTransfers(locationId: String?) async throws -> [LocationTransferRequest] {
        try maybeThrow()
        if let lid = locationId {
            return transfers.filter { $0.fromLocationId == lid || $0.toLocationId == lid }
        }
        return transfers
    }

    func createTransfer(_ request: CreateTransferRequest) async throws -> LocationTransferRequest {
        try maybeThrow()
        lastCreated = request
        let t = LocationTransferRequest(
            id: "new-t",
            fromLocationId: request.fromLocationId,
            toLocationId: request.toLocationId,
            items: request.items,
            status: "requested"
        )
        transfers.append(t)
        return t
    }

    func updateTransferStatus(id: String, status: String) async throws -> LocationTransferRequest {
        try maybeThrow()
        guard let idx = transfers.firstIndex(where: { $0.id == id }) else {
            throw URLError(.fileDoesNotExist)
        }
        let updated = LocationTransferRequest(
            id: id,
            fromLocationId: transfers[idx].fromLocationId,
            toLocationId: transfers[idx].toLocationId,
            items: transfers[idx].items,
            status: status
        )
        transfers[idx] = updated
        return updated
    }
}

@Suite("LocationTransferListViewModel")
@MainActor
struct LocationTransferListViewModelTests {

    @Test("load populates transfers")
    func loadPopulates() async {
        let repo = TransferStubRepo()
        repo.transfers = [makeTransfer(id: "t1")]
        let locs = [makeLoc(id: "A"), makeLoc(id: "B")]
        let vm = LocationTransferListViewModel(repo: repo, locations: locs, activeLocationId: "")
        await vm.load()
        if case .loaded = vm.loadState {
            #expect(vm.transfers.count == 1)
        } else {
            Issue.record("Expected loaded state")
        }
    }

    @Test("load sets error state when repo throws")
    func loadError() async {
        let repo = TransferStubRepo()
        repo.shouldThrow = true
        let vm = LocationTransferListViewModel(repo: repo, locations: [], activeLocationId: "")
        await vm.load()
        if case .error = vm.loadState {} else {
            Issue.record("Expected error state")
        }
    }

    @Test("append prepends new transfer to list")
    func append() async {
        let repo = TransferStubRepo()
        let vm = LocationTransferListViewModel(repo: repo, locations: [], activeLocationId: "")
        await vm.load()
        vm.append(makeTransfer(id: "prepended"))
        #expect(vm.transfers.first?.id == "prepended")
    }

    @Test("direction filter outgoing shows only from-location transfers")
    func directionFilterOutgoing() async {
        let repo = TransferStubRepo()
        repo.transfers = [
            makeTransfer(id: "out", from: "X", to: "Y"),
            makeTransfer(id: "in",  from: "Y", to: "X")
        ]
        let vm = LocationTransferListViewModel(repo: repo, locations: [], activeLocationId: "X")
        await vm.load()
        vm.direction = .outgoing
        #expect(vm.filtered.count == 1)
        #expect(vm.filtered.first?.id == "out")
    }

    @Test("direction filter incoming shows only to-location transfers")
    func directionFilterIncoming() async {
        let repo = TransferStubRepo()
        repo.transfers = [
            makeTransfer(id: "out", from: "X", to: "Y"),
            makeTransfer(id: "in",  from: "Y", to: "X")
        ]
        let vm = LocationTransferListViewModel(repo: repo, locations: [], activeLocationId: "X")
        await vm.load()
        vm.direction = .incoming
        #expect(vm.filtered.count == 1)
        #expect(vm.filtered.first?.id == "in")
    }

    @Test("updateStatus changes transfer status in list")
    func updateStatus() async {
        let repo = TransferStubRepo()
        repo.transfers = [makeTransfer(id: "t1", status: "requested")]
        let vm = LocationTransferListViewModel(repo: repo, locations: [], activeLocationId: "")
        await vm.load()
        await vm.updateStatus(id: "t1", status: "shipped")
        #expect(vm.transfers.first(where: { $0.id == "t1" })?.status == "shipped")
    }

    @Test("updateStatus sets error when repo throws")
    func updateStatusError() async {
        let repo = TransferStubRepo()
        repo.transfers = [makeTransfer(id: "t1")]
        let vm = LocationTransferListViewModel(repo: repo, locations: [], activeLocationId: "")
        await vm.load()
        repo.shouldThrow = true
        await vm.updateStatus(id: "t1", status: "shipped")
        if case .error = vm.loadState {} else {
            Issue.record("Expected error state after throw")
        }
    }
}
