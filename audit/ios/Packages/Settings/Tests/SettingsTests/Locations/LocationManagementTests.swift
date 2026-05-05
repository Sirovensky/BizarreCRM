import Testing
import Foundation
@testable import Settings

// MARK: - §60 Shared test helpers

private func makeLoc(
    id: String,
    name: String = "Loc",
    city: String = "City",
    region: String = "ST",
    active: Bool = true,
    isPrimary: Bool = false
) -> Location {
    Location(
        id: id, name: name, addressLine1: "1 Main",
        city: city, region: region, postal: "00000",
        country: "US", phone: "555", timezone: "UTC",
        active: active, isPrimary: isPrimary
    )
}

private func makeAssignment(
    userId: String,
    locationId: String,
    locationName: String = "Loc",
    isPrimary: Bool = false,
    roleAtLocation: String? = nil
) -> UserLocationAssignment {
    UserLocationAssignment(
        userId: userId,
        location: makeLoc(id: locationId, name: locationName),
        isPrimary: isPrimary,
        roleAtLocation: roleAtLocation,
        assignedAt: "2026-01-01 09:00:00"
    )
}

// MARK: - Stub repo (implements LocationUserAssignmentRepository)

private final class StubAssignmentRepo: LocationUserAssignmentRepository, @unchecked Sendable {

    var locations: [Location]
    var userAssignments: [String: [UserLocationAssignment]]   // userId → assignments
    var defaultLocation: Location?
    var shouldThrow: Bool = false
    var lastAssignCall: (userId: String, locationId: String, isPrimary: Bool)? = nil
    var lastRemoveCall: (userId: String, locationId: String)? = nil

    init(
        locations: [Location] = [],
        userAssignments: [String: [UserLocationAssignment]] = [:],
        defaultLocation: Location? = nil
    ) {
        self.locations = locations
        self.userAssignments = userAssignments
        self.defaultLocation = defaultLocation
    }

    private func maybeThrow() throws {
        if shouldThrow { throw URLError(.badServerResponse) }
    }

    // LocationRepository conformance (minimal stubs)
    func fetchLocations() async throws -> [Location] { try maybeThrow(); return locations }
    func fetchLocation(id: String) async throws -> Location { try maybeThrow(); return locations[0] }
    func createLocation(_ r: CreateLocationRequest) async throws -> Location { try maybeThrow(); return locations[0] }
    func updateLocation(id: String, request: UpdateLocationRequest) async throws -> Location { try maybeThrow(); return locations[0] }
    func deleteLocation(id: String) async throws { try maybeThrow() }
    func setPrimary(id: String) async throws -> Location { try maybeThrow(); return locations[0] }
    func setActive(id: String, active: Bool) async throws -> Location { try maybeThrow(); return locations[0] }
    func fetchInventoryBalances(locationId: String?) async throws -> [LocationInventoryBalance] { [] }
    func fetchTransfers(locationId: String?) async throws -> [LocationTransferRequest] { [] }
    func createTransfer(_ r: CreateTransferRequest) async throws -> LocationTransferRequest {
        LocationTransferRequest(id: "t", fromLocationId: r.fromLocationId, toLocationId: r.toLocationId, items: r.items)
    }
    func updateTransferStatus(id: String, status: String) async throws -> LocationTransferRequest {
        LocationTransferRequest(id: id, fromLocationId: "a", toLocationId: "b", items: [], status: status)
    }
    func fetchLocationAccess(employeeId: String) async throws -> [LocationAccessEntry] { [] }
    func updateLocationAccess(employeeId: String, entries: [LocationAccessEntry]) async throws -> [LocationAccessEntry] { entries }

    // LocationUserAssignmentRepository conformance
    func fetchDefaultLocation() async throws -> Location? {
        try maybeThrow()
        return defaultLocation
    }

    func fetchUserLocations(userId: String) async throws -> [UserLocationAssignment] {
        try maybeThrow()
        return userAssignments[userId] ?? []
    }

    @discardableResult
    func assignUserLocation(userId: String, locationId: String, isPrimary: Bool) async throws -> UserLocationRow {
        try maybeThrow()
        lastAssignCall = (userId, locationId, isPrimary)
        return UserLocationRow(userId: 1, locationId: 1, isPrimary: isPrimary, roleAtLocation: nil, assignedAt: "2026-01-01")
    }

    func removeUserLocation(userId: String, locationId: String) async throws {
        try maybeThrow()
        lastRemoveCall = (userId, locationId)
    }
}

// ===========================================================================
// MARK: - CurrentLocationPickerViewModel tests
// ===========================================================================

@Suite("CurrentLocationPickerViewModel")
@MainActor
struct CurrentLocationPickerViewModelTests {

    @Test("load transitions to loaded and populates locations + activeLocationId")
    func loadSuccess() async {
        let loc1 = makeLoc(id: "loc-1", name: "Main St")
        let repo = StubAssignmentRepo(
            locations: [loc1],
            defaultLocation: loc1
        )
        let vm = CurrentLocationPickerViewModel(repo: repo, userId: "u1")
        #expect(vm.loadState == .idle)

        await vm.load()

        #expect(vm.loadState == .loaded)
        #expect(vm.locations.count == 1)
        #expect(vm.activeLocationId == "loc-1")
    }

    @Test("load sets error state when repo throws")
    func loadError() async {
        let repo = StubAssignmentRepo()
        repo.shouldThrow = true
        let vm = CurrentLocationPickerViewModel(repo: repo, userId: "u1")
        await vm.load()
        if case .error = vm.loadState {} else {
            Issue.record("Expected error state")
        }
    }

    @Test("load sets activeLocationId to empty when no default location")
    func loadNoDefault() async {
        let repo = StubAssignmentRepo(
            locations: [makeLoc(id: "loc-1")],
            defaultLocation: nil
        )
        let vm = CurrentLocationPickerViewModel(repo: repo, userId: "u1")
        await vm.load()
        #expect(vm.activeLocationId == "")
    }

    @Test("selectLocation updates activeLocationId on success")
    func selectLocationSuccess() async {
        let repo = StubAssignmentRepo(
            locations: [makeLoc(id: "loc-1"), makeLoc(id: "loc-2")]
        )
        let vm = CurrentLocationPickerViewModel(repo: repo, userId: "u1")
        await vm.load()
        await vm.selectLocation("loc-2")
        #expect(vm.activeLocationId == "loc-2")
        #expect(repo.lastAssignCall?.userId == "u1")
        #expect(repo.lastAssignCall?.locationId == "loc-2")
        #expect(repo.lastAssignCall?.isPrimary == true)
    }

    @Test("selectLocation is a no-op when selecting same location")
    func selectLocationNoOp() async {
        let loc = makeLoc(id: "loc-1")
        let repo = StubAssignmentRepo(locations: [loc], defaultLocation: loc)
        let vm = CurrentLocationPickerViewModel(repo: repo, userId: "u1")
        await vm.load()
        // Confirm it's loc-1
        #expect(vm.activeLocationId == "loc-1")
        await vm.selectLocation("loc-1")
        // No assignment call should be made
        #expect(repo.lastAssignCall == nil)
    }

    @Test("selectLocation sets errorMessage when repo throws")
    func selectLocationError() async {
        let repo = StubAssignmentRepo(
            locations: [makeLoc(id: "loc-1"), makeLoc(id: "loc-2")]
        )
        let vm = CurrentLocationPickerViewModel(repo: repo, userId: "u1")
        await vm.load()
        repo.shouldThrow = true
        await vm.selectLocation("loc-2")
        #expect(vm.errorMessage != nil)
        // activeLocationId should NOT have changed
        #expect(vm.activeLocationId != "loc-2")
    }

    @Test("clearError removes errorMessage")
    func clearError() async {
        let repo = StubAssignmentRepo(locations: [makeLoc(id: "l1"), makeLoc(id: "l2")])
        let vm = CurrentLocationPickerViewModel(repo: repo, userId: "u1")
        await vm.load()
        repo.shouldThrow = true
        await vm.selectLocation("l2")
        #expect(vm.errorMessage != nil)
        vm.clearError()
        #expect(vm.errorMessage == nil)
    }
}

// ===========================================================================
// MARK: - LocationPermissionsMatrixViewModel tests
// ===========================================================================

@Suite("LocationPermissionsMatrixViewModel")
@MainActor
struct LocationPermissionsMatrixViewModelTests {

    private func makeUsers() -> [PermissionMatrixUser] {
        [
            PermissionMatrixUser(id: "u1", displayName: "Alice"),
            PermissionMatrixUser(id: "u2", displayName: "Bob")
        ]
    }

    @Test("load populates assignments for all users")
    func loadPopulatesAssignments() async {
        let locA = makeLoc(id: "loc-A", name: "Alpha")
        let locB = makeLoc(id: "loc-B", name: "Beta")
        let repo = StubAssignmentRepo(
            locations: [locA, locB],
            userAssignments: [
                "u1": [makeAssignment(userId: "u1", locationId: "loc-A")],
                "u2": [makeAssignment(userId: "u2", locationId: "loc-B")]
            ]
        )
        let vm = LocationPermissionsMatrixViewModel(
            repo: repo, locations: [locA, locB], users: makeUsers()
        )
        await vm.load()
        #expect(vm.loadState == .loaded)
        #expect(vm.isAssigned(userId: "u1", locationId: "loc-A") == true)
        #expect(vm.isAssigned(userId: "u1", locationId: "loc-B") == false)
        #expect(vm.isAssigned(userId: "u2", locationId: "loc-B") == true)
    }

    @Test("load sets error state when repo throws")
    func loadError() async {
        let repo = StubAssignmentRepo()
        repo.shouldThrow = true
        let vm = LocationPermissionsMatrixViewModel(
            repo: repo, locations: [], users: makeUsers()
        )
        await vm.load()
        if case .error = vm.loadState {} else {
            Issue.record("Expected error state")
        }
    }

    @Test("toggle on assigns user to location optimistically")
    func toggleOn() async {
        let locA = makeLoc(id: "loc-A")
        let repo = StubAssignmentRepo(locations: [locA], userAssignments: ["u1": []])
        let vm = LocationPermissionsMatrixViewModel(
            repo: repo, locations: [locA], users: makeUsers()
        )
        await vm.load()
        #expect(vm.isAssigned(userId: "u1", locationId: "loc-A") == false)
        await vm.toggle(userId: "u1", locationId: "loc-A", on: true)
        #expect(vm.isAssigned(userId: "u1", locationId: "loc-A") == true)
        #expect(repo.lastAssignCall?.userId == "u1")
        #expect(repo.lastAssignCall?.locationId == "loc-A")
    }

    @Test("toggle off removes user from location optimistically")
    func toggleOff() async {
        let locA = makeLoc(id: "loc-A")
        let repo = StubAssignmentRepo(
            locations: [locA],
            userAssignments: ["u1": [makeAssignment(userId: "u1", locationId: "loc-A")]]
        )
        let vm = LocationPermissionsMatrixViewModel(
            repo: repo, locations: [locA], users: makeUsers()
        )
        await vm.load()
        #expect(vm.isAssigned(userId: "u1", locationId: "loc-A") == true)
        await vm.toggle(userId: "u1", locationId: "loc-A", on: false)
        #expect(vm.isAssigned(userId: "u1", locationId: "loc-A") == false)
        #expect(repo.lastRemoveCall?.userId == "u1")
        #expect(repo.lastRemoveCall?.locationId == "loc-A")
    }

    @Test("toggle sets errorMessage when repo throws")
    func toggleError() async {
        let locA = makeLoc(id: "loc-A")
        let repo = StubAssignmentRepo(
            locations: [locA],
            userAssignments: ["u1": []]
        )
        let vm = LocationPermissionsMatrixViewModel(
            repo: repo, locations: [locA], users: makeUsers()
        )
        await vm.load()
        repo.shouldThrow = true
        await vm.toggle(userId: "u1", locationId: "loc-A", on: true)
        #expect(vm.errorMessage != nil)
    }

    @Test("isPrimary returns false when assignment is not primary")
    func isPrimaryFalse() async {
        let locA = makeLoc(id: "loc-A")
        let repo = StubAssignmentRepo(
            locations: [locA],
            userAssignments: ["u1": [makeAssignment(userId: "u1", locationId: "loc-A", isPrimary: false)]]
        )
        let vm = LocationPermissionsMatrixViewModel(
            repo: repo, locations: [locA], users: makeUsers()
        )
        await vm.load()
        #expect(vm.isPrimary(userId: "u1", locationId: "loc-A") == false)
    }

    @Test("isPrimary returns true when assignment is primary")
    func isPrimaryTrue() async {
        let locA = makeLoc(id: "loc-A")
        let repo = StubAssignmentRepo(
            locations: [locA],
            userAssignments: ["u1": [makeAssignment(userId: "u1", locationId: "loc-A", isPrimary: true)]]
        )
        let vm = LocationPermissionsMatrixViewModel(
            repo: repo, locations: [locA], users: makeUsers()
        )
        await vm.load()
        #expect(vm.isPrimary(userId: "u1", locationId: "loc-A") == true)
    }

    @Test("roleAtLocation returns nil when not assigned")
    func roleAtLocationNil() async {
        let locA = makeLoc(id: "loc-A")
        let repo = StubAssignmentRepo(locations: [locA], userAssignments: ["u1": []])
        let vm = LocationPermissionsMatrixViewModel(
            repo: repo, locations: [locA], users: makeUsers()
        )
        await vm.load()
        #expect(vm.roleAtLocation(userId: "u1", locationId: "loc-A") == nil)
    }

    @Test("roleAtLocation returns role when set")
    func roleAtLocationSet() async {
        let locA = makeLoc(id: "loc-A")
        let repo = StubAssignmentRepo(
            locations: [locA],
            userAssignments: ["u1": [makeAssignment(userId: "u1", locationId: "loc-A", roleAtLocation: "technician")]]
        )
        let vm = LocationPermissionsMatrixViewModel(
            repo: repo, locations: [locA], users: makeUsers()
        )
        await vm.load()
        #expect(vm.roleAtLocation(userId: "u1", locationId: "loc-A") == "technician")
    }

    @Test("clearError removes errorMessage")
    func clearError() async {
        let locA = makeLoc(id: "loc-A")
        let repo = StubAssignmentRepo(locations: [locA], userAssignments: ["u1": []])
        let vm = LocationPermissionsMatrixViewModel(
            repo: repo, locations: [locA], users: makeUsers()
        )
        await vm.load()
        repo.shouldThrow = true
        await vm.toggle(userId: "u1", locationId: "loc-A", on: true)
        #expect(vm.errorMessage != nil)
        vm.clearError()
        #expect(vm.errorMessage == nil)
    }
}

// ===========================================================================
// MARK: - UserLocationAssignment model tests
// ===========================================================================

@Suite("UserLocationAssignment")
struct UserLocationAssignmentTests {

    @Test("id is composite userId-locationId")
    func idIsComposite() {
        let assignment = makeAssignment(userId: "alice", locationId: "store-1")
        #expect(assignment.id == "alice-store-1")
    }

    @Test("isPrimary defaults to false")
    func isPrimaryDefault() {
        let assignment = makeAssignment(userId: "u1", locationId: "l1", isPrimary: false)
        #expect(assignment.isPrimary == false)
    }

    @Test("roleAtLocation is nil when not supplied")
    func roleAtLocationIsNilWhenNotSupplied() {
        let assignment = makeAssignment(userId: "u1", locationId: "l1")
        #expect(assignment.roleAtLocation == nil)
    }
}
