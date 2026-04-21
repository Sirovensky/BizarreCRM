import Testing
import Foundation
@testable import RolesEditor

// MARK: - Stub Repository

actor StubRolesRepository: RolesRepository {
    var storedRoles: [Role]
    var shouldThrow: Bool = false
    var updateCallCount: Int = 0
    var lastUpdateBefore: Set<String> = []
    var lastUpdateAfter: Set<String> = []

    init(roles: [Role] = []) {
        self.storedRoles = roles
    }

    func fetchAll() async throws -> [Role] {
        if shouldThrow { throw RolesEditorError.serverError("fetch failed") }
        return storedRoles
    }

    func create(name: String, preset: String?, capabilities: Set<String>) async throws -> Role {
        if shouldThrow { throw RolesEditorError.serverError("create failed") }
        if storedRoles.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            throw RolesEditorError.duplicateName
        }
        let role = Role(id: UUID().uuidString, name: name, preset: preset, capabilities: capabilities)
        storedRoles.append(role)
        return role
    }

    func update(role: Role, newCapabilities: Set<String>) async throws -> Role {
        if shouldThrow { throw RolesEditorError.serverError("update failed") }
        updateCallCount += 1
        lastUpdateBefore = role.capabilities
        lastUpdateAfter = newCapabilities
        let updated = Role(id: role.id, name: role.name, preset: role.preset, capabilities: newCapabilities)
        if let idx = storedRoles.firstIndex(where: { $0.id == role.id }) {
            storedRoles[idx] = updated
        }
        return updated
    }

    func delete(roleId: String) async throws {
        if shouldThrow { throw RolesEditorError.serverError("delete failed") }
        storedRoles.removeAll { $0.id == roleId }
    }

    func refresh() async throws -> [Role] {
        try await fetchAll()
    }
}

// MARK: - RolesMatrixViewModelTests

@Suite("RolesMatrixViewModel")
@MainActor
struct RolesMatrixViewModelTests {

    private func makeVM(roles: [Role] = []) -> (RolesMatrixViewModel, StubRolesRepository) {
        let repo = StubRolesRepository(roles: roles)
        let vm = RolesMatrixViewModel(repository: repo)
        return (vm, repo)
    }

    private func sampleRole(caps: Set<String> = ["tickets.view.any"]) -> Role {
        Role(id: "r1", name: "Test Role", capabilities: caps)
    }

    // MARK: Load

    @Test("load populates roles")
    func loadPopulatesRoles() async {
        let roles = [sampleRole()]
        let (vm, _) = makeVM(roles: roles)
        await vm.load()
        #expect(vm.roles.count == 1)
        #expect(vm.roles[0].name == "Test Role")
    }

    @Test("load sets isLoading to false after completion")
    func loadClearsLoading() async {
        let (vm, _) = makeVM()
        await vm.load()
        #expect(!vm.isLoading)
    }

    @Test("load sets errorMessage on failure")
    func loadSetsErrorOnFailure() async {
        let (vm, repo) = makeVM()
        await repo.set(shouldThrow: true)
        await vm.load()
        #expect(vm.errorMessage != nil)
    }

    // MARK: Toggle (§47.4 audit: every toggle → PATCH)

    @Test("toggle adds capability and calls update")
    func toggleAddsCap() async {
        let role = sampleRole(caps: [])
        let (vm, repo) = makeVM(roles: [role])
        await vm.load()
        await vm.toggle(capability: "tickets.view.any", on: role)
        let count = await repo.updateCallCount
        #expect(count == 1)
        #expect(vm.roles[0].capabilities.contains("tickets.view.any"))
    }

    @Test("toggle removes capability and calls update")
    func toggleRemovesCap() async {
        let role = sampleRole(caps: ["tickets.view.any"])
        let (vm, repo) = makeVM(roles: [role])
        await vm.load()
        await vm.toggle(capability: "tickets.view.any", on: role)
        let count = await repo.updateCallCount
        #expect(count == 1)
        #expect(!vm.roles[0].capabilities.contains("tickets.view.any"))
    }

    @Test("toggle sends before state for audit trail")
    func toggleSendsBeforeState() async {
        let role = sampleRole(caps: ["tickets.view.any"])
        let (vm, repo) = makeVM(roles: [role])
        await vm.load()
        await vm.toggle(capability: "tickets.delete", on: role)
        let before = await repo.lastUpdateBefore
        #expect(before.contains("tickets.view.any"))
        #expect(!before.contains("tickets.delete"))
    }

    // MARK: Create

    @Test("createRole adds role to list")
    func createRoleAdds() async {
        let (vm, _) = makeVM()
        await vm.load()
        await vm.createRole(name: "New Role", capabilities: ["customers.view"])
        #expect(vm.roles.count == 1)
        #expect(vm.roles[0].name == "New Role")
    }

    @Test("createRole sets errorMessage on duplicate name")
    func createRoleDuplicateName() async {
        let role = sampleRole()
        let (vm, _) = makeVM(roles: [role])
        await vm.load()
        await vm.createRole(name: "Test Role")
        #expect(vm.errorMessage != nil)
    }

    // MARK: Delete

    @Test("deleteRole removes role from list")
    func deleteRoleRemoves() async {
        let role = sampleRole()
        let (vm, _) = makeVM(roles: [role])
        await vm.load()
        await vm.deleteRole(role)
        #expect(vm.roles.isEmpty)
    }

    // MARK: Clone

    @Test("cloneRole creates new role with nil preset")
    func cloneRoleCreatesNew() async {
        let role = RolePresets.manager.makeRole()
        let (vm, _) = makeVM(roles: [role])
        await vm.load()
        await vm.cloneRole(role, newName: "My Manager Clone")
        #expect(vm.roles.count == 2)
        let clone = vm.roles.first { $0.name == "My Manager Clone" }
        #expect(clone != nil)
        #expect(clone?.preset == nil)
        #expect(clone?.capabilities == role.capabilities)
    }

    // MARK: Preview (§47.3)

    @Test("startPreview sets activePreviewRoleId")
    func startPreviewSetsId() async {
        let (vm, _) = makeVM()
        vm.startPreview(roleId: "r1")
        #expect(vm.activePreviewRoleId == "r1")
    }

    @Test("exitPreview clears activePreviewRoleId")
    func exitPreviewClearsId() async {
        let (vm, _) = makeVM()
        vm.startPreview(roleId: "r1")
        vm.exitPreview()
        #expect(vm.activePreviewRoleId == nil)
    }

    @Test("startPreview invokes onPreviewRoleChanged callback")
    func previewCallbackFired() async {
        let (vm, _) = makeVM()
        var receivedId: String?
        vm.onPreviewRoleChanged = { id in receivedId = id }
        vm.startPreview(roleId: "my-role")
        #expect(receivedId == "my-role")
    }

    @Test("exitPreview invokes onPreviewRoleChanged with nil")
    func exitPreviewCallbackNil() async {
        let (vm, _) = makeVM()
        var receivedId: String? = "something"
        vm.onPreviewRoleChanged = { id in receivedId = id }
        vm.startPreview(roleId: "my-role")
        vm.exitPreview()
        #expect(receivedId == nil)
    }

    // MARK: Domains

    @Test("domains returns 13 groups")
    func domainsReturns13Groups() async {
        let (vm, _) = makeVM()
        #expect(vm.domains.count == 13)
    }

    @Test("setCapabilities updates role on server")
    func setCapabilitiesPatches() async {
        let role = sampleRole(caps: ["tickets.view.any"])
        let (vm, repo) = makeVM(roles: [role])
        await vm.load()
        let newCaps: Set<String> = ["customers.view", "invoices.view"]
        await vm.setCapabilities(newCaps, on: role)
        let count = await repo.updateCallCount
        #expect(count == 1)
        #expect(vm.roles[0].capabilities == newCaps)
    }
}

// MARK: - StubRolesRepository helper for setting flags from @MainActor

private extension StubRolesRepository {
    func set(shouldThrow: Bool) {
        self.shouldThrow = shouldThrow
    }
}
