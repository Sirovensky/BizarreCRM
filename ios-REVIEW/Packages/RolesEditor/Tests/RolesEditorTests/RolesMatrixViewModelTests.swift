import Testing
import Foundation
@testable import RolesEditor

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

    // MARK: LoadRole

    @Test("loadRole updates role in array")
    func loadRoleUpdatesArray() async {
        let role = sampleRole(caps: ["tickets.view.any"])
        let (vm, _) = makeVM(roles: [role])
        await vm.load()
        await vm.loadRole(id: "r1")
        #expect(vm.roles[0].id == "r1")
    }

    @Test("loadRole sets errorMessage on failure")
    func loadRoleSetsError() async {
        let (vm, repo) = makeVM(roles: [sampleRole()])
        await vm.load()
        await repo.set(shouldThrow: true)
        await vm.loadRole(id: "r1")
        #expect(vm.errorMessage != nil)
    }

    // MARK: Toggle (§47.4 — every toggle produces a server call)

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

    @Test("toggle sets errorMessage on server failure")
    func toggleSetsError() async {
        let role = sampleRole(caps: ["tickets.view.any"])
        let (vm, repo) = makeVM(roles: [role])
        await vm.load()
        await repo.set(shouldThrow: true)
        await vm.toggle(capability: "customers.view", on: role)
        #expect(vm.errorMessage != nil)
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

    @Test("createRole with description passes description")
    func createRoleWithDescription() async {
        let (vm, repo) = makeVM()
        await vm.load()
        await vm.createRole(name: "Described Role", description: "A test role")
        let stored = await repo.storedRoles
        #expect(stored.count == 1)
        #expect(stored[0].name == "Described Role")
    }

    @Test("createRole sets errorMessage on duplicate name")
    func createRoleDuplicateName() async {
        let role = sampleRole()
        let (vm, _) = makeVM(roles: [role])
        await vm.load()
        await vm.createRole(name: "Test Role")
        #expect(vm.errorMessage != nil)
    }

    @Test("createRole clears isLoading after completion")
    func createRoleClearsLoading() async {
        let (vm, _) = makeVM()
        await vm.createRole(name: "Alpha")
        #expect(!vm.isLoading)
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

    @Test("deleteRole sets errorMessage on failure")
    func deleteRoleSetsError() async {
        let role = sampleRole()
        let (vm, repo) = makeVM(roles: [role])
        await vm.load()
        await repo.set(shouldThrow: true)
        await vm.deleteRole(role)
        #expect(vm.errorMessage != nil)
    }

    // MARK: setCapabilities

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

    // MARK: Preview (§47.3)

    @Test("startPreview sets activePreviewRoleId")
    func startPreviewSetsId() {
        let (vm, _) = makeVM()
        vm.startPreview(roleId: "r1")
        #expect(vm.activePreviewRoleId == "r1")
    }

    @Test("exitPreview clears activePreviewRoleId")
    func exitPreviewClearsId() {
        let (vm, _) = makeVM()
        vm.startPreview(roleId: "r1")
        vm.exitPreview()
        #expect(vm.activePreviewRoleId == nil)
    }

    @Test("startPreview invokes onPreviewRoleChanged callback")
    func previewCallbackFired() {
        let (vm, _) = makeVM()
        var receivedId: String?
        vm.onPreviewRoleChanged = { id in receivedId = id }
        vm.startPreview(roleId: "my-role")
        #expect(receivedId == "my-role")
    }

    @Test("exitPreview invokes onPreviewRoleChanged with nil")
    func exitPreviewCallbackNil() {
        let (vm, _) = makeVM()
        var receivedId: String? = "something"
        vm.onPreviewRoleChanged = { id in receivedId = id }
        vm.startPreview(roleId: "my-role")
        vm.exitPreview()
        #expect(receivedId == nil)
    }

    @Test("activePreviewRole returns role matching activePreviewRoleId")
    func activePreviewRoleReturnsRole() async {
        let role = sampleRole()
        let (vm, _) = makeVM(roles: [role])
        await vm.load()
        vm.startPreview(roleId: "r1")
        #expect(vm.activePreviewRole?.id == "r1")
    }

    @Test("activePreviewRole returns nil when no preview active")
    func activePreviewRoleNilWhenNoPreview() async {
        let (vm, _) = makeVM(roles: [sampleRole()])
        await vm.load()
        #expect(vm.activePreviewRole == nil)
    }

    // MARK: Domains

    @Test("domains returns 13 groups")
    func domainsReturns13Groups() {
        let (vm, _) = makeVM()
        #expect(vm.domains.count == 13)
    }

    @Test("domains covers all expected groups")
    func domainsCoversExpectedGroups() {
        let (vm, _) = makeVM()
        let domainNames = Set(vm.domains.map(\.domain))
        let expected: Set<String> = [
            "Tickets", "Customers", "Inventory", "Invoices", "SMS",
            "Reports", "Settings", "Hardware", "Audit", "Data",
            "Team", "Marketing", "Danger"
        ]
        #expect(expected.isSubset(of: domainNames))
    }
}

// MARK: - RoleDetailViewModelTests

@Suite("RoleDetailViewModel")
@MainActor
struct RoleDetailViewModelTests {

    private func makeVM(caps: Set<String> = ["tickets.view.any"]) -> (RoleDetailViewModel, StubRolesRepository) {
        let role = Role(id: "r1", name: "Test", capabilities: caps)
        let repo = StubRolesRepository(roles: [role])
        let vm = RoleDetailViewModel(role: role, repository: repo)
        return (vm, repo)
    }

    // MARK: Toggle

    @Test("toggle adds capability and marks hasUnsavedChanges")
    func toggleAddsCap() {
        let (vm, _) = makeVM(caps: [])
        vm.toggle(capability: "tickets.view.any")
        #expect(vm.role.capabilities.contains("tickets.view.any"))
        #expect(vm.hasUnsavedChanges)
    }

    @Test("toggle removes capability")
    func toggleRemovesCap() {
        let (vm, _) = makeVM(caps: ["tickets.view.any"])
        vm.toggle(capability: "tickets.view.any")
        #expect(!vm.role.capabilities.contains("tickets.view.any"))
        #expect(vm.hasUnsavedChanges)
    }

    @Test("toggle is immutable — returns new Role")
    func toggleIsImmutable() {
        let (vm, _) = makeVM(caps: ["tickets.view.any"])
        let originalId = vm.role.id
        vm.toggle(capability: "customers.view")
        #expect(vm.role.id == originalId)
        #expect(vm.role.capabilities.contains("tickets.view.any"))
        #expect(vm.role.capabilities.contains("customers.view"))
    }

    // MARK: has

    @Test("has returns true for present capability")
    func hasReturnsTrue() {
        let (vm, _) = makeVM(caps: ["tickets.view.any"])
        #expect(vm.has(capability: "tickets.view.any"))
    }

    @Test("has returns false for absent capability")
    func hasReturnsFalse() {
        let (vm, _) = makeVM(caps: [])
        #expect(!vm.has(capability: "tickets.view.any"))
    }

    // MARK: Save

    @Test("save clears hasUnsavedChanges on success")
    func saveClearsUnsaved() async {
        let (vm, _) = makeVM(caps: ["tickets.view.any"])
        vm.toggle(capability: "customers.view")
        await vm.save()
        #expect(!vm.hasUnsavedChanges)
        #expect(!vm.isSaving)
    }

    @Test("save sets errorMessage on failure")
    func saveSetsError() async {
        let (vm, repo) = makeVM(caps: ["tickets.view.any"])
        vm.toggle(capability: "customers.view")
        await repo.set(shouldThrow: true)
        await vm.save()
        #expect(vm.errorMessage != nil)
    }

    @Test("save clears isSaving after completion")
    func saveClearsSaving() async {
        let (vm, _) = makeVM()
        vm.toggle(capability: "customers.view")
        await vm.save()
        #expect(!vm.isSaving)
    }

    // MARK: Discard

    @Test("discard restores original capabilities")
    func discardRestoresOriginal() {
        let (vm, _) = makeVM(caps: ["tickets.view.any"])
        vm.toggle(capability: "customers.view")
        vm.discard()
        #expect(vm.role.capabilities == ["tickets.view.any"])
        #expect(!vm.hasUnsavedChanges)
    }

    @Test("discard clears hasUnsavedChanges")
    func discardClearsUnsaved() {
        let (vm, _) = makeVM(caps: ["tickets.view.any"])
        vm.toggle(capability: "customers.view")
        #expect(vm.hasUnsavedChanges)
        vm.discard()
        #expect(!vm.hasUnsavedChanges)
    }

    // MARK: applyPreset

    @Test("applyPreset replaces capabilities")
    func applyPresetReplacesCapabilities() {
        let (vm, _) = makeVM(caps: [])
        vm.applyPreset(RolePresets.technician)
        #expect(vm.role.capabilities == RolePresets.technician.capabilities)
        #expect(vm.role.preset == RolePresets.technician.id)
        #expect(vm.hasUnsavedChanges)
    }

    @Test("applyPreset marks hasUnsavedChanges when preset differs from original")
    func applyPresetMarksDirty() {
        let (vm, _) = makeVM(caps: [])
        vm.applyPreset(RolePresets.cashier)
        #expect(vm.hasUnsavedChanges)
    }

    // MARK: domainedCapabilities

    @Test("domainedCapabilities returns all 13 domain groups")
    func domainedCapabilitiesCount() {
        let (vm, _) = makeVM()
        #expect(vm.domainedCapabilities.count == 13)
    }
}
