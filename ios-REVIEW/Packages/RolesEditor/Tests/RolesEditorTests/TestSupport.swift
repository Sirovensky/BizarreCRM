import Foundation
@testable import RolesEditor

// MARK: - StubRolesRepository
//
// Shared test double for all RolesEditor test suites.
// Thread-safe via actor isolation.

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

    func fetchOne(id: String) async throws -> Role {
        if shouldThrow { throw RolesEditorError.serverError("fetch failed") }
        guard let role = storedRoles.first(where: { $0.id == id }) else {
            throw RolesEditorError.roleNotFound
        }
        return role
    }

    func create(name: String, description: String?, capabilities: Set<String>) async throws -> Role {
        if shouldThrow { throw RolesEditorError.serverError("create failed") }
        if storedRoles.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            throw RolesEditorError.duplicateName
        }
        let role = Role(id: UUID().uuidString, name: name, preset: nil, capabilities: capabilities)
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

    // MARK: Test helpers

    func set(shouldThrow: Bool) {
        self.shouldThrow = shouldThrow
    }
}
