import Foundation
import Networking
import Factory

// MARK: - RolesRepository protocol

public protocol RolesRepository: Sendable {
    func fetchAll() async throws -> [Role]
    func create(name: String, preset: String?, capabilities: Set<String>) async throws -> Role
    func update(role: Role, newCapabilities: Set<String>) async throws -> Role
    func delete(roleId: String) async throws
    func refresh() async throws -> [Role]
}

// MARK: - Live implementation

public actor RolesRepositoryLive: RolesRepository {
    private let api: any APIClient
    private var cachedRoles: [Role] = []

    public init(api: any APIClient) {
        self.api = api
    }

    public func fetchAll() async throws -> [Role] {
        let roles = try await api.listRoles()
        cachedRoles = roles
        return roles
    }

    public func create(name: String, preset: String? = nil, capabilities: Set<String>) async throws -> Role {
        // Guard duplicate names against cache
        if cachedRoles.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            throw RolesEditorError.duplicateName
        }
        let role = try await api.createRole(name: name, preset: preset, capabilities: capabilities)
        cachedRoles.append(role)
        NotificationCenter.default.post(name: .rolesChanged, object: nil)
        return role
    }

    public func update(role: Role, newCapabilities: Set<String>) async throws -> Role {
        let updated = try await api.updateCapabilities(
            roleId: role.id,
            before: role.capabilities,
            after: newCapabilities
        )
        if let idx = cachedRoles.firstIndex(where: { $0.id == role.id }) {
            cachedRoles[idx] = updated
        }
        NotificationCenter.default.post(name: .rolesChanged, object: nil)
        return updated
    }

    public func delete(roleId: String) async throws {
        try await api.deleteRole(id: roleId)
        cachedRoles.removeAll { $0.id == roleId }
        NotificationCenter.default.post(name: .rolesChanged, object: nil)
    }

    public func refresh() async throws -> [Role] {
        try await fetchAll()
    }
}

// MARK: - Factory DI container

public extension Container {
    var rolesRepository: Factory<any RolesRepository> {
        self {
            // Requires APIClient to be registered in the host app's container.
            // Fallback to a stub if not registered (avoids crash in SwiftUI previews).
            RolesRepositoryLive(api: self.apiClient())
        }
    }

    var apiClient: Factory<any APIClient> {
        self { APIClientImpl() }
    }
}
