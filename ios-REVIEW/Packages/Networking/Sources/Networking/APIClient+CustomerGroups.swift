import Foundation

/// Networking-layer extension for SMS customer groups.
///
/// Routes confirmed: packages/server/src/routes/smsGroups.routes.ts
/// Mounted at: /api/v1/sms/groups
///
/// Envelope: `{ success: Bool, data: T?, message: String? }`
///
/// NOTE: This file provides generic path primitives. Typed wrappers
/// (`listCustomerGroups`, `createCustomerGroup`, etc.) that reference
/// Customers-package models live in
/// `Customers/Groups/CustomerGroupEndpoints.swift`.
/// This file is append-only — add new sms/groups route helpers below.
public extension APIClient {

    // MARK: - List

    /// `GET /api/v1/sms/groups` — list all SMS customer groups.
    /// Decoded into caller-supplied `T` to avoid a circular package dependency.
    func fetchCustomerGroups<T: Decodable & Sendable>(as type: T.Type) async throws -> T {
        try await get("/api/v1/sms/groups", as: type)
    }

    // MARK: - Detail

    /// `GET /api/v1/sms/groups/:id` — group detail with paginated members.
    func fetchCustomerGroupDetail<T: Decodable & Sendable>(
        id: Int64,
        page: Int = 1,
        limit: Int = 50,
        as type: T.Type
    ) async throws -> T {
        let query = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        return try await get("/api/v1/sms/groups/\(id)", query: query, as: type)
    }

    // MARK: - Create

    /// `POST /api/v1/sms/groups` — create a new group (rate-limited: 20/hr).
    func createCustomerGroupRaw<B: Encodable & Sendable, T: Decodable & Sendable>(
        body: B,
        as type: T.Type
    ) async throws -> T {
        try await post("/api/v1/sms/groups", body: body, as: type)
    }

    // MARK: - Rename / partial update

    /// `PATCH /api/v1/sms/groups/:id` — partial update (manager+).
    func renameCustomerGroupRaw<B: Encodable & Sendable, T: Decodable & Sendable>(
        id: Int64,
        body: B,
        as type: T.Type
    ) async throws -> T {
        try await patch("/api/v1/sms/groups/\(id)", body: body, as: type)
    }

    // MARK: - Delete

    /// `DELETE /api/v1/sms/groups/:id` — hard delete with cascade (manager+).
    func deleteCustomerGroupRaw(id: Int64) async throws {
        try await delete("/api/v1/sms/groups/\(id)")
    }

    // MARK: - Members: add

    /// `POST /api/v1/sms/groups/:id/members` — batch add (static groups only, rate-limited: 10/min).
    func addCustomerGroupMembersRaw<B: Encodable & Sendable, T: Decodable & Sendable>(
        groupId: Int64,
        body: B,
        as type: T.Type
    ) async throws -> T {
        try await post("/api/v1/sms/groups/\(groupId)/members", body: body, as: type)
    }

    // MARK: - Members: remove

    /// `DELETE /api/v1/sms/groups/:id/members/:customerId` — remove one member (static only).
    func removeCustomerGroupMemberRaw(groupId: Int64, customerId: Int64) async throws {
        try await delete("/api/v1/sms/groups/\(groupId)/members/\(customerId)")
    }
}
