import Foundation
import Networking

// MARK: - RolesEndpoints
//
// Thin domain-object adapters between the wire types in Networking/APIClient+Roles.swift
// and the RolesEditor domain model (Role, Capability).
//
// Grounded against packages/server/src/routes/roles.routes.ts:
//   GET    /api/v1/roles                    → [RoleRow]        (list)
//   POST   /api/v1/roles                    → RoleRow          (create)
//   DELETE /api/v1/roles/:id               → void             (delete)
//   GET    /api/v1/roles/:id/permissions    → RolePermissionsPayload
//   PUT    /api/v1/roles/:id/permissions    → UpdatePermissionsResult (toggle/batch)
//
// NOTE: Role.id in this package is String (UUID-style) for SwiftUI List/ForEach
// identity. The server uses Int. We bridge with String(Int) — never invent ids.

// MARK: - RoleRow → Role adapter

extension RoleRow {
    /// Converts a server `RoleRow` + optional allowed-key set into a domain `Role`.
    func toDomainRole(capabilities: Set<String> = []) -> Role {
        Role(
            id: String(id),
            name: name,
            preset: nil,
            capabilities: capabilities
        )
    }
}

// MARK: - APIClient domain-level helpers

public extension APIClient {

    // MARK: List

    /// Fetches all custom roles.
    /// Route: `GET /api/v1/roles`
    func domainListRoles() async throws -> [Role] {
        let rows = try await listRoles()
        return rows.map { $0.toDomainRole() }
    }

    // MARK: Create

    /// Creates a new custom role with the given name/description,
    /// then immediately seeds its permissions from `capabilities`.
    /// Route: `POST /api/v1/roles` then `PUT /api/v1/roles/:id/permissions`.
    func domainCreateRole(
        name: String,
        description: String? = nil,
        capabilities: Set<String>
    ) async throws -> Role {
        let row = try await createRole(name: name, description: description)
        // Seed capabilities — send a full batch with all catalog keys so the
        // matrix is deterministic from the first load.
        let updates = CapabilityCatalog.all.map { cap in
            PermissionUpdate(key: cap.id, allowed: capabilities.contains(cap.id))
        }
        _ = try await updateRolePermissions(roleId: row.id, updates: updates)
        return row.toDomainRole(capabilities: capabilities)
    }

    // MARK: Fetch with capabilities

    /// Fetches a single role with its full capability matrix.
    /// Route: `GET /api/v1/roles/:id/permissions`
    func domainFetchRole(id: Int) async throws -> Role {
        let payload = try await fetchRolePermissions(roleId: id)
        let allowed = Set(payload.matrix.filter(\.allowed).map(\.key))
        return payload.role.toDomainRole(capabilities: allowed)
    }

    // MARK: Update capabilities (toggle / batch set)

    /// Applies a diff between `before` and `after` capability sets as a batch
    /// `PUT /api/v1/roles/:id/permissions`.
    ///
    /// Only sends keys that changed — matches server expectation of a targeted
    /// `updates` array. Sends ALL catalog keys when both sets are provided so
    /// the matrix is always fully synced.
    func domainUpdateCapabilities(
        roleId: String,
        before: Set<String>,
        after: Set<String>
    ) async throws -> Role {
        guard let intId = Int(roleId) else {
            throw RolesEditorError.serverError("Invalid role id: \(roleId)")
        }
        // Build full-catalog update so server matrix stays in sync.
        let updates = CapabilityCatalog.all.map { cap in
            PermissionUpdate(key: cap.id, allowed: after.contains(cap.id))
        }
        _ = try await updateRolePermissions(roleId: intId, updates: updates)
        // Re-fetch the authoritative matrix.
        return try await domainFetchRole(id: intId)
    }

    // MARK: Delete

    /// Deletes a custom role by its string-encoded id.
    /// Route: `DELETE /api/v1/roles/:id`
    func domainDeleteRole(id: String) async throws {
        guard let intId = Int(id) else {
            throw RolesEditorError.serverError("Invalid role id: \(id)")
        }
        try await deleteRole(id: intId)
    }
}
