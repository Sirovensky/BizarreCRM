import Foundation
import Networking

// MARK: - Wire types

public struct RoleListResponse: Decodable, Sendable {
    public let roles: [Role]
}

public struct RoleResponse: Decodable, Sendable {
    public let role: Role
}

public struct CapabilityListResponse: Decodable, Sendable {
    public let capabilities: [Capability]
}

public struct UpdateCapabilitiesRequest: Encodable, Sendable {
    public let capabilities: [String]
    public let before: [String]   // §47.4 audit: before state

    public init(before: Set<String>, after: Set<String>) {
        self.capabilities = Array(after).sorted()
        self.before = Array(before).sorted()
    }
}

public struct CreateRoleRequest: Encodable, Sendable {
    public let name: String
    public let preset: String?
    public let capabilities: [String]

    public init(name: String, preset: String? = nil, capabilities: Set<String>) {
        self.name = name
        self.preset = preset
        self.capabilities = Array(capabilities).sorted()
    }
}

public struct PreviewAsResponse: Decodable, Sendable {
    public let capabilities: [String]
    public let roleName: String?
}

private struct EmptyBody: Encodable, Sendable {
    public init() {}
}

// MARK: - APIClient extension

public extension APIClient {

    func listRoles() async throws -> [Role] {
        let response = try await get("/roles", as: RoleListResponse.self)
        return response.roles
    }

    func createRole(name: String, preset: String? = nil, capabilities: Set<String>) async throws -> Role {
        let body = CreateRoleRequest(name: name, preset: preset, capabilities: capabilities)
        let response = try await post("/roles", body: body, as: RoleResponse.self)
        return response.role
    }

    func fetchRole(id: String) async throws -> Role {
        let response = try await get("/roles/\(id)", as: RoleResponse.self)
        return response.role
    }

    func updateCapabilities(roleId: String, before: Set<String>, after: Set<String>) async throws -> Role {
        let body = UpdateCapabilitiesRequest(before: before, after: after)
        let response = try await patch("/roles/\(roleId)", body: body, as: RoleResponse.self)
        return response.role
    }

    func deleteRole(id: String) async throws {
        try await delete("/roles/\(id)")
    }

    func listServerCapabilities() async throws -> [Capability] {
        let response = try await get("/roles/capabilities", as: CapabilityListResponse.self)
        return response.capabilities
    }

    func previewAsRole(roleId: String) async throws -> PreviewAsResponse {
        return try await post("/roles/\(roleId)/preview-as", body: EmptyBody(), as: PreviewAsResponse.self)
    }
}
