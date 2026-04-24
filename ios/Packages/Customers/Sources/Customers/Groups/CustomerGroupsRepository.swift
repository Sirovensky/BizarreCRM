import Foundation
import Networking

// §5 Customer Groups & Tags — repository layer

public protocol CustomerGroupsRepository: Sendable {
    func listGroups() async throws -> [CustomerGroup]
    func groupDetail(id: Int64, page: Int, limit: Int) async throws -> CustomerGroupDetail
    func createGroup(_ req: CreateGroupRequest) async throws -> CustomerGroup
    func updateGroup(id: Int64, _ req: UpdateGroupRequest) async throws -> CustomerGroup
    func deleteGroup(id: Int64) async throws
    func addMembers(groupId: Int64, customerIds: [Int64]) async throws -> AddGroupMembersResponse
    func removeMember(groupId: Int64, customerId: Int64) async throws
}

public actor CustomerGroupsRepositoryImpl: CustomerGroupsRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func listGroups() async throws -> [CustomerGroup] {
        try await api.listCustomerGroups()
    }

    public func groupDetail(id: Int64, page: Int = 1, limit: Int = 50) async throws -> CustomerGroupDetail {
        try await api.getCustomerGroupDetail(id: id, page: page, limit: limit)
    }

    public func createGroup(_ req: CreateGroupRequest) async throws -> CustomerGroup {
        try await api.createCustomerGroup(req)
    }

    public func updateGroup(id: Int64, _ req: UpdateGroupRequest) async throws -> CustomerGroup {
        try await api.updateCustomerGroup(id: id, req)
    }

    public func deleteGroup(id: Int64) async throws {
        try await api.deleteCustomerGroup(id: id)
    }

    public func addMembers(groupId: Int64, customerIds: [Int64]) async throws -> AddGroupMembersResponse {
        try await api.addGroupMembers(groupId: groupId, customerIds: customerIds)
    }

    public func removeMember(groupId: Int64, customerId: Int64) async throws {
        try await api.removeGroupMember(groupId: groupId, customerId: customerId)
    }
}
