import Foundation

// MARK: - Roles wire types
//
// Grounded against packages/server/src/routes/roles.routes.ts.
//
// Confirmed routes:
//   GET    /api/v1/roles                        → { success, data: [RoleRow] }
//   POST   /api/v1/roles                        → { success, data: RoleRow }
//   PUT    /api/v1/roles/:id                    → { success, data: RoleRow }
//   DELETE /api/v1/roles/:id                    → { success, data: { id } }
//   GET    /api/v1/roles/:id/permissions        → { success, data: { role: RoleRow, matrix: [{key,allowed}] } }
//   PUT    /api/v1/roles/:id/permissions        → { success, data: { role_id, applied } }
//   GET    /api/v1/roles/permission-keys        → { success, data: [String] }

/// Server row from `custom_roles` table.
public struct RoleRow: Decodable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let description: String?
    public let isActive: Int
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case isActive   = "is_active"
        case createdAt  = "created_at"
    }

    public var isActiveFlag: Bool { isActive != 0 }

    /// Memberwise init for use in tests and previews (the Decodable CodingKeys
    /// path suppresses the synthesized memberwise init).
    public init(id: Int, name: String, description: String?, isActive: Int, createdAt: String) {
        self.id = id
        self.name = name
        self.description = description
        self.isActive = isActive
        self.createdAt = createdAt
    }
}

/// One cell in the permission matrix: a canonical key + whether it's allowed.
public struct PermissionMatrixEntry: Decodable, Sendable {
    public let key: String
    public let allowed: Bool
}

/// Response shape for `GET /api/v1/roles/:id/permissions`.
public struct RolePermissionsPayload: Decodable, Sendable {
    public let role: RoleRow
    public let matrix: [PermissionMatrixEntry]
}

/// Request body for `POST /api/v1/roles`.
public struct CreateRoleBody: Encodable, Sendable {
    public let name: String
    public let description: String?

    public init(name: String, description: String? = nil) {
        self.name = name
        self.description = description
    }
}

/// Request body for `PUT /api/v1/roles/:id`.
public struct UpdateRoleBody: Encodable, Sendable {
    public let description: String?
    public let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case description
        case isActive = "is_active"
    }

    public init(description: String? = nil, isActive: Bool? = nil) {
        self.description = description
        self.isActive = isActive
    }
}

/// One update entry for `PUT /api/v1/roles/:id/permissions`.
public struct PermissionUpdate: Encodable, Sendable {
    public let key: String
    public let allowed: Bool

    public init(key: String, allowed: Bool) {
        self.key = key
        self.allowed = allowed
    }
}

/// Request body for `PUT /api/v1/roles/:id/permissions`.
public struct UpdatePermissionsBody: Encodable, Sendable {
    public let updates: [PermissionUpdate]

    public init(updates: [PermissionUpdate]) {
        self.updates = updates
    }
}

/// Response for `PUT /api/v1/roles/:id/permissions`.
public struct UpdatePermissionsResult: Decodable, Sendable {
    public let roleId: Int
    public let applied: Int

    enum CodingKeys: String, CodingKey {
        case roleId  = "role_id"
        case applied
    }
}

/// Response for `DELETE /api/v1/roles/:id`.
public struct DeleteRoleResult: Decodable, Sendable {
    public let id: Int
}

// MARK: - APIClient extension

public extension APIClient {

    // MARK: Role list

    /// `GET /api/v1/roles` — returns all custom roles in creation order.
    func listRoles() async throws -> [RoleRow] {
        try await get("/api/v1/roles", as: [RoleRow].self)
    }

    // MARK: Role create

    /// `POST /api/v1/roles` — creates a new custom role (admin only).
    func createRole(name: String, description: String? = nil) async throws -> RoleRow {
        let body = CreateRoleBody(name: name, description: description)
        return try await post("/api/v1/roles", body: body, as: RoleRow.self)
    }

    // MARK: Role update

    /// `PUT /api/v1/roles/:id` — updates description and/or active flag (admin only).
    func updateRole(id: Int, description: String? = nil, isActive: Bool? = nil) async throws -> RoleRow {
        let body = UpdateRoleBody(description: description, isActive: isActive)
        return try await put("/api/v1/roles/\(id)", body: body, as: RoleRow.self)
    }

    // MARK: Role delete

    /// `DELETE /api/v1/roles/:id` — deletes a custom role (admin only; built-ins are rejected by server).
    func deleteRole(id: Int) async throws {
        try await delete("/api/v1/roles/\(id)")
    }

    // MARK: Permission matrix

    /// `GET /api/v1/roles/:id/permissions` — returns the role row + full capability matrix.
    func fetchRolePermissions(roleId: Int) async throws -> RolePermissionsPayload {
        try await get("/api/v1/roles/\(roleId)/permissions", as: RolePermissionsPayload.self)
    }

    /// `PUT /api/v1/roles/:id/permissions` — batch-update one or more permission keys (admin only).
    func updateRolePermissions(roleId: Int, updates: [PermissionUpdate]) async throws -> UpdatePermissionsResult {
        let body = UpdatePermissionsBody(updates: updates)
        return try await put("/api/v1/roles/\(roleId)/permissions", body: body, as: UpdatePermissionsResult.self)
    }

    /// `GET /api/v1/roles/permission-keys` — canonical permission key list from the server.
    func fetchPermissionKeys() async throws -> [String] {
        try await get("/api/v1/roles/permission-keys", as: [String].self)
    }
}
