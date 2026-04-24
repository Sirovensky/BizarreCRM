import Testing
import Foundation
@testable import RolesEditor
import Networking


// MARK: - RolesRepositoryContractTests
//
// Tests for the RolesRepository protocol contract using StubRolesRepository
// (defined in TestSupport.swift). These verify the contract that any live or
// stub implementation must honour.

@Suite("RolesRepository contract")
@MainActor
struct RolesRepositoryContractTests {

    // MARK: fetchAll

    @Test("fetchAll returns empty list when no roles exist")
    func fetchAllEmpty() async throws {
        let repo = StubRolesRepository()
        let roles = try await repo.fetchAll()
        #expect(roles.isEmpty)
    }

    @Test("fetchAll returns seeded roles")
    func fetchAllWithRoles() async throws {
        let repo = StubRolesRepository(roles: [
            Role(id: "1", name: "Admin", capabilities: []),
            Role(id: "2", name: "Technician", capabilities: [])
        ])
        let roles = try await repo.fetchAll()
        #expect(roles.count == 2)
    }

    @Test("fetchAll throws on error")
    func fetchAllThrowsOnError() async throws {
        let repo = StubRolesRepository()
        await repo.set(shouldThrow: true)
        await #expect(throws: (any Error).self) {
            _ = try await repo.fetchAll()
        }
    }

    // MARK: fetchOne

    @Test("fetchOne returns role by id")
    func fetchOneReturnsRole() async throws {
        let repo = StubRolesRepository(roles: [
            Role(id: "42", name: "Manager", capabilities: ["customers.view"])
        ])
        let role = try await repo.fetchOne(id: "42")
        #expect(role.name == "Manager")
        #expect(role.capabilities.contains("customers.view"))
    }

    @Test("fetchOne throws roleNotFound for unknown id")
    func fetchOneUnknown() async throws {
        let repo = StubRolesRepository()
        await #expect(throws: RolesEditorError.roleNotFound) {
            _ = try await repo.fetchOne(id: "999")
        }
    }

    @Test("fetchOne throws on shouldThrow")
    func fetchOneThrows() async throws {
        let repo = StubRolesRepository(roles: [Role(id: "1", name: "A", capabilities: [])])
        await repo.set(shouldThrow: true)
        await #expect(throws: (any Error).self) {
            _ = try await repo.fetchOne(id: "1")
        }
    }

    // MARK: create

    @Test("create stores new role")
    func createStoresRole() async throws {
        let repo = StubRolesRepository()
        let role = try await repo.create(name: "Custom", description: nil, capabilities: ["sms.read"])
        #expect(role.name == "Custom")
        #expect(role.capabilities.contains("sms.read"))
        let all = try await repo.fetchAll()
        #expect(all.count == 1)
    }

    @Test("create rejects duplicate name case-insensitively")
    func createRejectsDuplicate() async throws {
        let repo = StubRolesRepository(roles: [
            Role(id: "1", name: "Admin", capabilities: [])
        ])
        await #expect(throws: RolesEditorError.duplicateName) {
            _ = try await repo.create(name: "ADMIN", description: nil, capabilities: [])
        }
    }

    @Test("create throws serverError when shouldThrow is set")
    func createThrowsOnError() async throws {
        let repo = StubRolesRepository()
        await repo.set(shouldThrow: true)
        await #expect(throws: (any Error).self) {
            _ = try await repo.create(name: "Fail", description: nil, capabilities: [])
        }
    }

    @Test("create with nil description succeeds")
    func createNilDescription() async throws {
        let repo = StubRolesRepository()
        let role = try await repo.create(name: "No Desc", description: nil, capabilities: [])
        #expect(role.name == "No Desc")
    }

    // MARK: update

    @Test("update replaces capabilities on role")
    func updateReplacesCaps() async throws {
        let role = Role(id: "1", name: "Tech", capabilities: ["tickets.view.any"])
        let repo = StubRolesRepository(roles: [role])
        let updated = try await repo.update(role: role, newCapabilities: ["customers.view"])
        #expect(updated.capabilities == ["customers.view"])
        #expect(!updated.capabilities.contains("tickets.view.any"))
    }

    @Test("update increments updateCallCount")
    func updateIncrementsCount() async throws {
        let role = Role(id: "1", name: "Tech", capabilities: [])
        let repo = StubRolesRepository(roles: [role])
        _ = try await repo.update(role: role, newCapabilities: ["sms.send"])
        let count = await repo.updateCallCount
        #expect(count == 1)
    }

    @Test("update records before state for audit trail")
    func updateRecordsBeforeState() async throws {
        let role = Role(id: "1", name: "Tech", capabilities: ["tickets.view.any", "customers.view"])
        let repo = StubRolesRepository(roles: [role])
        _ = try await repo.update(role: role, newCapabilities: ["sms.read"])
        let before = await repo.lastUpdateBefore
        #expect(before.contains("tickets.view.any"))
        #expect(before.contains("customers.view"))
    }

    @Test("update records after state")
    func updateRecordsAfterState() async throws {
        let role = Role(id: "1", name: "Tech", capabilities: [])
        let repo = StubRolesRepository(roles: [role])
        _ = try await repo.update(role: role, newCapabilities: ["sms.send", "tickets.create"])
        let after = await repo.lastUpdateAfter
        #expect(after.contains("sms.send"))
        #expect(after.contains("tickets.create"))
    }

    @Test("update throws on shouldThrow")
    func updateThrows() async throws {
        let role = Role(id: "1", name: "A", capabilities: [])
        let repo = StubRolesRepository(roles: [role])
        await repo.set(shouldThrow: true)
        await #expect(throws: (any Error).self) {
            _ = try await repo.update(role: role, newCapabilities: [])
        }
    }

    // MARK: delete

    @Test("delete removes role from store")
    func deleteRemovesRole() async throws {
        let role = Role(id: "7", name: "ToDelete", capabilities: [])
        let repo = StubRolesRepository(roles: [role])
        try await repo.delete(roleId: "7")
        let all = try await repo.fetchAll()
        #expect(all.isEmpty)
    }

    @Test("delete leaves other roles intact")
    func deleteLeavesOthers() async throws {
        let repo = StubRolesRepository(roles: [
            Role(id: "1", name: "Keep", capabilities: []),
            Role(id: "2", name: "Remove", capabilities: [])
        ])
        try await repo.delete(roleId: "2")
        let all = try await repo.fetchAll()
        #expect(all.count == 1)
        #expect(all[0].id == "1")
    }

    @Test("delete throws on shouldThrow")
    func deleteThrowsOnError() async throws {
        let repo = StubRolesRepository(roles: [Role(id: "1", name: "A", capabilities: [])])
        await repo.set(shouldThrow: true)
        await #expect(throws: (any Error).self) {
            try await repo.delete(roleId: "1")
        }
    }

    // MARK: refresh

    @Test("refresh returns current roles")
    func refreshReturnsCurrentRoles() async throws {
        let repo = StubRolesRepository(roles: [
            Role(id: "1", name: "X", capabilities: [])
        ])
        let refreshed = try await repo.refresh()
        #expect(refreshed.count == 1)
    }

    @Test("refresh after create returns updated list")
    func refreshAfterCreate() async throws {
        let repo = StubRolesRepository()
        _ = try await repo.create(name: "NewRole", description: nil, capabilities: [])
        let refreshed = try await repo.refresh()
        #expect(refreshed.count == 1)
        #expect(refreshed[0].name == "NewRole")
    }
}

// MARK: - RoleRow adapter tests

@Suite("RoleRow toDomainRole adapter")
struct RoleRowAdapterTests {

    @Test("toDomainRole sets id as String of Int")
    func idBridging() {
        let row = RoleRow(id: 42, name: "Technician", description: nil, isActive: 1, createdAt: "2026-01-01")
        let role = row.toDomainRole()
        #expect(role.id == "42")
    }

    @Test("toDomainRole preserves name")
    func preservesName() {
        let row = RoleRow(id: 1, name: "Manager", description: "Manages stuff", isActive: 1, createdAt: "2026-01-01")
        let role = row.toDomainRole()
        #expect(role.name == "Manager")
    }

    @Test("toDomainRole seeds provided capabilities")
    func seedsCapabilities() {
        let row = RoleRow(id: 3, name: "Cashier", description: nil, isActive: 1, createdAt: "2026-01-01")
        let caps: Set<String> = ["invoices.payment.accept", "customers.view"]
        let role = row.toDomainRole(capabilities: caps)
        #expect(role.capabilities == caps)
    }

    @Test("toDomainRole defaults to empty capabilities")
    func defaultsToEmptyCaps() {
        let row = RoleRow(id: 5, name: "Viewer", description: nil, isActive: 1, createdAt: "2026-01-01")
        let role = row.toDomainRole()
        #expect(role.capabilities.isEmpty)
    }

    @Test("isActiveFlag is true when is_active == 1")
    func isActiveFlagTrue() {
        let row = RoleRow(id: 1, name: "A", description: nil, isActive: 1, createdAt: "")
        #expect(row.isActiveFlag)
    }

    @Test("isActiveFlag is false when is_active == 0")
    func isActiveFlagFalse() {
        let row = RoleRow(id: 1, name: "A", description: nil, isActive: 0, createdAt: "")
        #expect(!row.isActiveFlag)
    }
}

// MARK: - PermissionMatrixEntry tests

@Suite("PermissionMatrixEntry")
struct PermissionMatrixEntryTests {

    @Test("PermissionMatrixEntry decodes key and allowed true")
    func decodesTrue() throws {
        let json = #"{"key":"tickets.view.any","allowed":true}"#
        let data = Data(json.utf8)
        let entry = try JSONDecoder().decode(PermissionMatrixEntry.self, from: data)
        #expect(entry.key == "tickets.view.any")
        #expect(entry.allowed)
    }

    @Test("PermissionMatrixEntry decodes allowed false")
    func decodesFalse() throws {
        let json = #"{"key":"danger.tenant.delete","allowed":false}"#
        let data = Data(json.utf8)
        let entry = try JSONDecoder().decode(PermissionMatrixEntry.self, from: data)
        #expect(entry.key == "danger.tenant.delete")
        #expect(!entry.allowed)
    }
}

// MARK: - PermissionUpdate encoding tests

@Suite("PermissionUpdate encoding")
struct PermissionUpdateEncodingTests {

    @Test("PermissionUpdate encodes key and allowed true")
    func encodesTrue() throws {
        let update = PermissionUpdate(key: "tickets.create", allowed: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(update)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"key\":\"tickets.create\""))
        #expect(json.contains("\"allowed\":true"))
    }

    @Test("PermissionUpdate encodes allowed false")
    func encodesFalse() throws {
        let update = PermissionUpdate(key: "admin.full", allowed: false)
        let data = try JSONEncoder().encode(update)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"allowed\":false"))
    }

    @Test("UpdatePermissionsBody encodes updates array")
    func encodesBody() throws {
        let body = UpdatePermissionsBody(updates: [
            PermissionUpdate(key: "a", allowed: true),
            PermissionUpdate(key: "b", allowed: false)
        ])
        let data = try JSONEncoder().encode(body)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"updates\""))
    }

    @Test("CreateRoleBody encodes name and description")
    func encodesCreateBody() throws {
        let body = CreateRoleBody(name: "Lead Tech", description: "Senior technician role")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(body)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"name\":\"Lead Tech\""))
        #expect(json.contains("\"description\":\"Senior technician role\""))
    }

    @Test("UpdateRoleBody encodes is_active using snake_case key")
    func encodesIsActive() throws {
        let body = UpdateRoleBody(description: nil, isActive: true)
        let encoder = JSONEncoder()
        let data = try encoder.encode(body)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"is_active\""))
    }
}
