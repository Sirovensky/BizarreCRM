import Foundation
import Networking
import Factory

// MARK: - RolesRepository protocol

public protocol RolesRepository: Sendable {
    func fetchAll() async throws -> [Role]
    func fetchOne(id: String) async throws -> Role
    func create(name: String, description: String?, capabilities: Set<String>) async throws -> Role
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

    // MARK: Fetch all roles (capabilities loaded lazily on detail)

    public func fetchAll() async throws -> [Role] {
        let roles = try await api.domainListRoles()
        cachedRoles = roles
        return roles
    }

    // MARK: Fetch single role with full capability matrix

    public func fetchOne(id: String) async throws -> Role {
        guard let intId = Int(id) else {
            throw RolesEditorError.serverError("Invalid role id: \(id)")
        }
        let role = try await api.domainFetchRole(id: intId)
        if let idx = cachedRoles.firstIndex(where: { $0.id == id }) {
            cachedRoles[idx] = role
        }
        return role
    }

    // MARK: Create

    public func create(
        name: String,
        description: String? = nil,
        capabilities: Set<String>
    ) async throws -> Role {
        if cachedRoles.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            throw RolesEditorError.duplicateName
        }
        let role = try await api.domainCreateRole(
            name: name,
            description: description,
            capabilities: capabilities
        )
        cachedRoles.append(role)
        NotificationCenter.default.post(name: .rolesChanged, object: nil)
        return role
    }

    // MARK: Update capabilities

    public func update(role: Role, newCapabilities: Set<String>) async throws -> Role {
        let updated = try await api.domainUpdateCapabilities(
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

    // MARK: Delete

    public func delete(roleId: String) async throws {
        try await api.domainDeleteRole(id: roleId)
        cachedRoles.removeAll { $0.id == roleId }
        NotificationCenter.default.post(name: .rolesChanged, object: nil)
    }

    // MARK: Refresh

    public func refresh() async throws -> [Role] {
        try await fetchAll()
    }
}

// MARK: - Factory DI container

public extension Container {
    var rolesRepository: Factory<any RolesRepository> {
        self {
            RolesRepositoryLive(api: self.apiClient())
        }
    }

    var apiClient: Factory<any APIClient> {
        self { APIClientImpl() }
    }
}
