import Foundation
import Networking

// §5 Groups & Tags — Networking extension
//
// Server routes: packages/server/src/routes/smsGroups.routes.ts
// Base path: /api/v1/sms/groups
//
// Envelope shape: { success, data, message }
// GET /           → data is a JSON array of CustomerGroup objects
// GET /:id        → data is CustomerGroupDetail
// POST /          → data is CustomerGroup
// PATCH /:id      → data is CustomerGroup
// POST /:id/members → data is AddGroupMembersResponse

public extension APIClient {

    // MARK: - List

    /// `GET /api/v1/sms/groups` — list all groups with member counts.
    /// Server returns `data` as a JSON array directly.
    func listCustomerGroups() async throws -> [CustomerGroup] {
        try await get("/api/v1/sms/groups", as: [CustomerGroup].self)
    }

    // MARK: - Detail

    /// `GET /api/v1/sms/groups/:id` — detail with paginated members.
    func getCustomerGroupDetail(id: Int64, page: Int = 1, limit: Int = 50) async throws -> CustomerGroupDetail {
        let query = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        return try await get("/api/v1/sms/groups/\(id)", query: query, as: CustomerGroupDetail.self)
    }

    // MARK: - Create

    /// `POST /api/v1/sms/groups` — create a new static or dynamic group.
    func createCustomerGroup(_ req: CreateGroupRequest) async throws -> CustomerGroup {
        try await post("/api/v1/sms/groups", body: req, as: CustomerGroup.self)
    }

    // MARK: - Update

    /// `PATCH /api/v1/sms/groups/:id` — partial update (manager+).
    func updateCustomerGroup(id: Int64, _ req: UpdateGroupRequest) async throws -> CustomerGroup {
        try await patch("/api/v1/sms/groups/\(id)", body: req, as: CustomerGroup.self)
    }

    // MARK: - Delete

    /// `DELETE /api/v1/sms/groups/:id` — hard delete with cascade (manager+).
    func deleteCustomerGroup(id: Int64) async throws {
        try await delete("/api/v1/sms/groups/\(id)")
    }

    // MARK: - Members

    /// `POST /api/v1/sms/groups/:id/members` — batch add members (static only).
    func addGroupMembers(groupId: Int64, customerIds: [Int64]) async throws -> AddGroupMembersResponse {
        let req = AddGroupMembersRequest(customerIds: customerIds)
        return try await post("/api/v1/sms/groups/\(groupId)/members", body: req, as: AddGroupMembersResponse.self)
    }

    /// `DELETE /api/v1/sms/groups/:id/members/:customerId` — remove one member (static only).
    func removeGroupMember(groupId: Int64, customerId: Int64) async throws {
        try await delete("/api/v1/sms/groups/\(groupId)/members/\(customerId)")
    }
}
