import Testing
import Foundation
@testable import RolesEditor
import Networking

// MARK: - RoleUsersInspectorViewModelTests

@Suite("RoleUsersInspectorViewModel")
@MainActor
struct RoleUsersInspectorViewModelTests {

    // MARK: - Helpers

    private func makeVM(roleName: String = "Technician", roleId: String = "42") -> (RoleUsersInspectorViewModel, StubAPIForInspector) {
        let role = Role(id: roleId, name: roleName, preset: nil, capabilities: [])
        let api = StubAPIForInspector()
        let vm = RoleUsersInspectorViewModel(role: role, api: api)
        return (vm, api)
    }

    /// Creates an `Employee` via JSON decoding (Employee has no public init —
    /// all fields use explicit CodingKeys which suppress the memberwise init).
    private func employee(
        id: Int64 = 1,
        name: String = "Alice Smith",
        email: String? = "alice@example.com",
        role: String? = nil,
        isActive: Int = 1
    ) -> Employee {
        let parts = name.split(separator: " ")
        let first = parts.first.map(String.init) ?? name
        let last  = parts.dropFirst().first.map(String.init) ?? ""
        let emailJSON = email.map { "\"\($0)\"" } ?? "null"
        let roleJSON  = role.map  { "\"\($0)\"" } ?? "null"
        let json = """
        {
          "id": \(id),
          "username": null,
          "email": \(emailJSON),
          "first_name": "\(first)",
          "last_name": "\(last)",
          "role": \(roleJSON),
          "avatar_url": null,
          "is_active": \(isActive),
          "has_pin": null,
          "created_at": null
        }
        """
        // Employee uses explicit CodingKeys with snake_case — no key strategy needed.
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(Employee.self, from: Data(json.utf8))
    }

    // MARK: - Load

    @Test("load populates allUsers from API")
    func loadPopulatesAllUsers() async {
        let (vm, api) = makeVM()
        api.usersToReturn = [employee(id: 1), employee(id: 2)]
        await vm.load()
        #expect(vm.allUsers.count == 2)
        #expect(!vm.isLoading)
    }

    @Test("load sets errorMessage on failure")
    func loadSetsError() async {
        let (vm, api) = makeVM()
        api.shouldThrow = true
        await vm.load()
        #expect(vm.errorMessage != nil)
        #expect(!vm.isLoading)
    }

    @Test("load clears isLoading on success")
    func loadClearsLoading() async {
        let (vm, _) = makeVM()
        await vm.load()
        #expect(!vm.isLoading)
    }

    // MARK: - Members derivation

    @Test("members returns users whose role matches role name (case-insensitive)")
    func membersMatchByRoleName() async {
        let (vm, api) = makeVM(roleName: "Technician")
        api.usersToReturn = [
            employee(id: 1, role: "Technician"),
            employee(id: 2, role: "technician"),  // case-insensitive
            employee(id: 3, role: "Manager"),
            employee(id: 4, role: nil)
        ]
        await vm.load()
        #expect(vm.members.count == 2)
        #expect(vm.members.map(\.id).sorted() == [1, 2])
    }

    @Test("members matches when role field equals role id string")
    func membersMatchByRoleId() async {
        let (vm, api) = makeVM(roleName: "Custom", roleId: "99")
        api.usersToReturn = [
            employee(id: 1, role: "99"),   // stored as id string
            employee(id: 2, role: "Custom")
        ]
        await vm.load()
        #expect(vm.members.count == 2)
    }

    @Test("unassignedUsers excludes members and inactive users")
    func unassignedUsersExcludesMembersAndInactive() async {
        let (vm, api) = makeVM(roleName: "Technician")
        api.usersToReturn = [
            employee(id: 1, role: "Technician"),   // member → excluded
            employee(id: 2, role: nil, isActive: 1), // candidate
            employee(id: 3, role: nil, isActive: 0)  // inactive → excluded
        ]
        await vm.load()
        #expect(vm.unassignedUsers.count == 1)
        #expect(vm.unassignedUsers[0].id == 2)
    }

    @Test("members returns empty when no users match")
    func membersEmptyWhenNoMatch() async {
        let (vm, api) = makeVM(roleName: "Technician")
        api.usersToReturn = [employee(id: 1, role: "Manager")]
        await vm.load()
        #expect(vm.members.isEmpty)
    }

    // MARK: - Assign

    @Test("assign calls API with correct userId and roleId")
    func assignCallsAPICorrectly() async {
        let (vm, api) = makeVM(roleName: "Technician", roleId: "7")
        let user = employee(id: 99, role: nil)
        api.usersToReturn = [user]
        await vm.load()
        await vm.assign(user: user)
        #expect(api.lastAssignedUserId == 99)
        #expect(api.lastAssignedRoleId == 7)
    }

    @Test("assign moves user from unassigned to members optimistically")
    func assignUpdatesUserOptimistically() async {
        let (vm, api) = makeVM(roleName: "Technician", roleId: "7")
        let user = employee(id: 5, role: nil)
        api.usersToReturn = [user]
        await vm.load()
        #expect(!vm.members.contains(where: { $0.id == 5 }))
        await vm.assign(user: user)
        #expect(vm.members.contains(where: { $0.id == 5 }))
    }

    @Test("assign sets errorMessage on API failure")
    func assignSetsError() async {
        let (vm, api) = makeVM(roleName: "Technician", roleId: "7")
        let user = employee(id: 5, role: nil)
        api.usersToReturn = [user]
        await vm.load()
        api.shouldThrowOnAssign = true
        await vm.assign(user: user)
        #expect(vm.errorMessage != nil)
    }

    @Test("assign with invalid role id sets errorMessage")
    func assignInvalidRoleIdSetsError() async {
        let (vm, _) = makeVM(roleName: "Tech", roleId: "not-an-int")
        let user = employee(id: 1, role: nil)
        await vm.assign(user: user)
        #expect(vm.errorMessage != nil)
    }

    @Test("assign dismisses sheet on success")
    func assignDismissesSheet() async {
        let (vm, api) = makeVM(roleName: "Technician", roleId: "7")
        let user = employee(id: 5, role: nil)
        api.usersToReturn = [user]
        await vm.load()
        vm.showAssignSheet = true
        await vm.assign(user: user)
        #expect(!vm.showAssignSheet)
    }

    // MARK: - Unassign

    @Test("unassign calls API with roleId 0")
    func unassignCallsAPIWithZeroRoleId() async {
        let (vm, api) = makeVM(roleName: "Technician", roleId: "7")
        let user = employee(id: 3, role: "Technician")
        api.usersToReturn = [user]
        await vm.load()
        await vm.unassign(user: user)
        #expect(api.lastAssignedUserId == 3)
        #expect(api.lastAssignedRoleId == 0)
    }

    @Test("unassign removes user from members list optimistically")
    func unassignRemovesFromMembers() async {
        let (vm, api) = makeVM(roleName: "Technician", roleId: "7")
        let user = employee(id: 3, role: "Technician")
        api.usersToReturn = [user]
        await vm.load()
        #expect(vm.members.count == 1)
        await vm.unassign(user: user)
        #expect(vm.members.isEmpty)
    }

    @Test("unassign sets errorMessage on API failure")
    func unassignSetsError() async {
        let (vm, api) = makeVM(roleName: "Technician", roleId: "7")
        let user = employee(id: 3, role: "Technician")
        api.usersToReturn = [user]
        await vm.load()
        api.shouldThrowOnAssign = true
        await vm.unassign(user: user)
        #expect(vm.errorMessage != nil)
    }
}

// MARK: - RolesMatrixViewModel rename extension tests

@Suite("RolesMatrixViewModel.renameRole")
@MainActor
struct RenameRoleTests {

    private func makeVM(roles: [Role] = []) -> (RolesMatrixViewModel, StubRolesRepository) {
        let repo = StubRolesRepository(roles: roles)
        let vm = RolesMatrixViewModel(repository: repo)
        return (vm, repo)
    }

    @Test("renameRole with blank name is no-op")
    func renameBlankNameNoOp() async {
        let role = Role(id: "r1", name: "Tech", capabilities: [])
        let (vm, _) = makeVM(roles: [role])
        await vm.load()
        await vm.renameRole(role, newName: "   ")
        #expect(vm.roles[0].name == "Tech")
    }

    @Test("renameRole with same name is no-op")
    func renameSameNameNoOp() async {
        let role = Role(id: "r1", name: "Tech", capabilities: [])
        let (vm, _) = makeVM(roles: [role])
        await vm.load()
        await vm.renameRole(role, newName: "Tech")
        #expect(vm.roles[0].name == "Tech")
    }

    @Test("renameRole updates role name in list")
    func renameUpdatesName() async {
        let role = Role(id: "r1", name: "Tech", capabilities: ["tickets.view.any"])
        let (vm, _) = makeVM(roles: [role])
        await vm.load()
        await vm.renameRole(role, newName: "Lead Tech")
        // After rename the old id is deleted and a new one added
        let names = vm.roles.map(\.name)
        #expect(names.contains("Lead Tech"))
        #expect(!names.contains("Tech"))
    }

    @Test("renameRole sets errorMessage on duplicate name")
    func renameDuplicateNameSetsError() async {
        let r1 = Role(id: "r1", name: "Tech", capabilities: [])
        let r2 = Role(id: "r2", name: "Manager", capabilities: [])
        let (vm, _) = makeVM(roles: [r1, r2])
        await vm.load()
        await vm.renameRole(r1, newName: "Manager")
        #expect(vm.errorMessage != nil)
    }

    @Test("renameRole clears isLoading after completion")
    func renameClearsLoading() async {
        let role = Role(id: "r1", name: "Tech", capabilities: [])
        let (vm, _) = makeVM(roles: [role])
        await vm.load()
        await vm.renameRole(role, newName: "Lead Tech")
        #expect(!vm.isLoading)
    }
}

// MARK: - StubAPIForInspector
//
// Test double for the RoleUsersAPIClient protocol used by
// RoleUsersInspectorViewModel.

final class StubAPIForInspector: RoleUsersAPIClient, @unchecked Sendable {

    // MARK: Configuration

    var usersToReturn: [Employee] = []
    var shouldThrow = false
    var shouldThrowOnAssign = false

    // MARK: Recorded calls

    var lastAssignedUserId: Int64?
    var lastAssignedRoleId: Int?

    // MARK: RoleUsersAPIClient

    func listAllUsers() async throws -> [Employee] {
        if shouldThrow { throw RolesEditorError.serverError("list failed") }
        return usersToReturn
    }

    func assignEmployeeRole(userId: Int64, roleId: Int) async throws {
        if shouldThrowOnAssign { throw RolesEditorError.serverError("assign failed") }
        lastAssignedUserId = userId
        lastAssignedRoleId = roleId
    }
}
