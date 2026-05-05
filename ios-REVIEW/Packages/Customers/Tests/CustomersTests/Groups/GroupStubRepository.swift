import Foundation
@testable import Customers

// MARK: - Stub repository for Groups tests

actor GroupStubRepository: CustomerGroupsRepository {

    // MARK: - Canned responses

    var listResult: Result<[CustomerGroup], Error>
    var detailResult: Result<CustomerGroupDetail, Error>
    var createResult: Result<CustomerGroup, Error>
    var updateResult: Result<CustomerGroup, Error>
    var deleteError: Error?
    var addMembersResult: Result<AddGroupMembersResponse, Error>
    var removeMemberError: Error?

    // MARK: - Call tracking (for assertion)

    private(set) var listCallCount: Int = 0
    private(set) var detailCallCount: Int = 0
    private(set) var createCallCount: Int = 0
    private(set) var lastCreateRequest: CreateGroupRequest?
    private(set) var deleteCallCount: Int = 0
    private(set) var lastDeletedId: Int64?
    private(set) var addMembersCallCount: Int = 0
    private(set) var lastAddedCustomerIds: [Int64]?
    private(set) var removeMemberCallCount: Int = 0
    private(set) var lastRemovedCustomerId: Int64?

    // MARK: - Init

    init(
        listResult: Result<[CustomerGroup], Error> = .success([]),
        detailResult: Result<CustomerGroupDetail, Error> = .success(.stub()),
        createResult: Result<CustomerGroup, Error> = .success(.stub()),
        updateResult: Result<CustomerGroup, Error> = .success(.stub()),
        deleteError: Error? = nil,
        addMembersResult: Result<AddGroupMembersResponse, Error> = .success(.stub()),
        removeMemberError: Error? = nil
    ) {
        self.listResult = listResult
        self.detailResult = detailResult
        self.createResult = createResult
        self.updateResult = updateResult
        self.deleteError = deleteError
        self.addMembersResult = addMembersResult
        self.removeMemberError = removeMemberError
    }

    // MARK: - Protocol conformance

    func listGroups() async throws -> [CustomerGroup] {
        listCallCount += 1
        return try listResult.get()
    }

    func groupDetail(id: Int64, page: Int, limit: Int) async throws -> CustomerGroupDetail {
        detailCallCount += 1
        return try detailResult.get()
    }

    func createGroup(_ req: CreateGroupRequest) async throws -> CustomerGroup {
        createCallCount += 1
        lastCreateRequest = req
        return try createResult.get()
    }

    func updateGroup(id: Int64, _ req: UpdateGroupRequest) async throws -> CustomerGroup {
        return try updateResult.get()
    }

    func deleteGroup(id: Int64) async throws {
        deleteCallCount += 1
        lastDeletedId = id
        if let err = deleteError { throw err }
    }

    func addMembers(groupId: Int64, customerIds: [Int64]) async throws -> AddGroupMembersResponse {
        addMembersCallCount += 1
        lastAddedCustomerIds = customerIds
        return try addMembersResult.get()
    }

    func removeMember(groupId: Int64, customerId: Int64) async throws {
        removeMemberCallCount += 1
        lastRemovedCustomerId = customerId
        if let err = removeMemberError { throw err }
    }
}

// MARK: - Stub factories

extension CustomerGroup {
    static func stub(
        id: Int64 = 1,
        name: String = "VIP Customers",
        description: String? = nil,
        isDynamic: Bool = false,
        memberCountCache: Int = 5
    ) -> CustomerGroup {
        let json = """
        {
          "id": \(id),
          "name": "\(name)",
          "description": \(description.map { "\"" + $0 + "\"" } ?? "null"),
          "is_dynamic": \(isDynamic ? 1 : 0),
          "member_count_cache": \(memberCountCache),
          "created_by_user_id": 1,
          "created_at": "2026-01-01T00:00:00.000Z",
          "updated_at": "2026-01-01T00:00:00.000Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(CustomerGroup.self, from: Data(json.utf8))
    }
}

extension CustomerGroupMember {
    static func stub(
        memberId: Int64 = 1,
        customerId: Int64 = 10,
        firstName: String? = "Alice",
        lastName: String? = "Smith",
        email: String? = "alice@example.com"
    ) -> CustomerGroupMember {
        let fn = firstName.map { "\"\($0)\"" } ?? "null"
        let ln = lastName.map { "\"\($0)\"" } ?? "null"
        let em = email.map { "\"\($0)\"" } ?? "null"
        let json = """
        {
          "member_id": \(memberId),
          "customer_id": \(customerId),
          "added_at": "2026-01-01T00:00:00.000Z",
          "first_name": \(fn),
          "last_name": \(ln),
          "phone": null,
          "mobile": null,
          "email": \(em)
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(CustomerGroupMember.self, from: Data(json.utf8))
    }
}

extension CustomerGroupDetail {
    static func stub(
        group: CustomerGroup = .stub(),
        members: [CustomerGroupMember] = [.stub()],
        page: Int = 1,
        total: Int = 1
    ) -> CustomerGroupDetail {
        let pag = GroupMemberPagination(page: page, limit: 50, total: total, pages: 1)
        return CustomerGroupDetail(group: group, members: members, pagination: pag)
    }
}

extension AddGroupMembersResponse {
    static func stub(groupId: Int64 = 1, added: Int = 1, skipped: Int = 0) -> AddGroupMembersResponse {
        let json = """
        {"group_id": \(groupId), "added": \(added), "skipped": \(skipped)}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(AddGroupMembersResponse.self, from: Data(json.utf8))
    }
}

// MARK: - Generic stub error

struct StubGroupError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String = "stub error") { self.message = message }
}
