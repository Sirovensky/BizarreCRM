import XCTest
@testable import Customers
import Networking

// §5 Customer Groups & Tags — CustomerGroupsRepository unit tests
// Tests model decoding, computed properties, request encoding, and repo wiring.

final class CustomerGroupsRepositoryTests: XCTestCase {

    // MARK: - CustomerGroup decoding

    func test_customerGroup_decodesSnakeCaseFields() throws {
        let json = """
        {
          "id": 42,
          "name": "Premium",
          "description": "Top tier",
          "is_dynamic": 0,
          "member_count_cache": 17,
          "created_by_user_id": 3,
          "created_at": "2026-01-15T10:00:00.000Z",
          "updated_at": "2026-02-01T08:30:00.000Z"
        }
        """
        let group = try decodeGroup(json)
        XCTAssertEqual(group.id, 42)
        XCTAssertEqual(group.name, "Premium")
        XCTAssertEqual(group.description, "Top tier")
        XCTAssertFalse(group.isDynamic)
        XCTAssertEqual(group.memberCountCache, 17)
        XCTAssertEqual(group.createdByUserId, 3)
    }

    func test_customerGroup_dynamicTrue_decodesCorrectly() throws {
        let json = """
        {
          "id": 1, "name": "Dynamic", "description": null,
          "is_dynamic": 1, "member_count_cache": 0,
          "created_by_user_id": null, "created_at": null, "updated_at": null
        }
        """
        let group = try decodeGroup(json)
        XCTAssertTrue(group.isDynamic)
        XCTAssertNil(group.description)
    }

    // MARK: - CustomerGroupMember decoding

    func test_customerGroupMember_decodesSnakeCaseFields() throws {
        let json = """
        {
          "member_id": 5, "customer_id": 99,
          "added_at": "2026-03-01T00:00:00.000Z",
          "first_name": "Eve", "last_name": "Zhao",
          "phone": "555-0100", "mobile": null, "email": "eve@example.com"
        }
        """
        let member = try decodeMember(json)
        XCTAssertEqual(member.memberId, 5)
        XCTAssertEqual(member.customerId, 99)
        XCTAssertEqual(member.firstName, "Eve")
        XCTAssertEqual(member.lastName, "Zhao")
        XCTAssertEqual(member.phone, "555-0100")
        XCTAssertNil(member.mobile)
        XCTAssertEqual(member.email, "eve@example.com")
    }

    // MARK: - CustomerGroup.displayMemberCount

    func test_displayMemberCount_singular() {
        XCTAssertEqual(CustomerGroup.stub(memberCountCache: 1).displayMemberCount, "1 member")
    }

    func test_displayMemberCount_plural() {
        XCTAssertEqual(CustomerGroup.stub(memberCountCache: 42).displayMemberCount, "42 members")
    }

    func test_displayMemberCount_zero() {
        XCTAssertEqual(CustomerGroup.stub(memberCountCache: 0).displayMemberCount, "0 members")
    }

    // MARK: - CustomerGroupMember.displayName

    func test_displayName_firstAndLast() {
        let m = CustomerGroupMember.stub(firstName: "Alice", lastName: "Smith")
        XCTAssertEqual(m.displayName, "Alice Smith")
    }

    func test_displayName_firstNameOnly() throws {
        let json = """
        {"member_id":1,"customer_id":1,"added_at":null,
         "first_name":"Alice","last_name":null,"phone":null,"mobile":null,"email":null}
        """
        let m = try decodeMember(json)
        XCTAssertEqual(m.displayName, "Alice")
    }

    func test_displayName_fallsBackToEmail() throws {
        let json = """
        {"member_id":1,"customer_id":1,"added_at":null,
         "first_name":null,"last_name":null,"phone":null,"mobile":null,"email":"anon@x.com"}
        """
        let m = try decodeMember(json)
        XCTAssertEqual(m.displayName, "anon@x.com")
    }

    func test_displayName_fallsBackToCustomerId() throws {
        let json = """
        {"member_id":1,"customer_id":77,"added_at":null,
         "first_name":null,"last_name":null,"phone":null,"mobile":null,"email":null}
        """
        let m = try decodeMember(json)
        XCTAssertEqual(m.displayName, "Customer 77")
    }

    func test_contactLine_prefersMobile() throws {
        let json = """
        {"member_id":1,"customer_id":1,"added_at":null,
         "first_name":null,"last_name":null,"phone":"555-0100","mobile":"555-9999","email":"a@b.com"}
        """
        let m = try decodeMember(json)
        XCTAssertEqual(m.contactLine, "555-9999")
    }

    // MARK: - AddGroupMembersResponse decoding

    func test_addGroupMembersResponse_decodes() throws {
        let json = """{"group_id": 5, "added": 3, "skipped": 1}"""
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let resp = try decoder.decode(AddGroupMembersResponse.self, from: Data(json.utf8))
        XCTAssertEqual(resp.groupId, 5)
        XCTAssertEqual(resp.added, 3)
        XCTAssertEqual(resp.skipped, 1)
    }

    // MARK: - CreateGroupRequest encoding

    func test_createGroupRequest_encodesDynamic() throws {
        let req = CreateGroupRequest(name: "VIP", description: "Top tier", isDynamic: false)
        let encoder = JSONEncoder()
        let data = try encoder.encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["name"] as? String, "VIP")
        XCTAssertEqual(dict?["description"] as? String, "Top tier")
        XCTAssertEqual(dict?["is_dynamic"] as? Bool, false)
    }

    func test_createGroupRequest_nilDescriptionOmitted() throws {
        let req = CreateGroupRequest(name: "A", description: nil, isDynamic: false)
        let encoder = JSONEncoder()
        let data = try encoder.encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNil(dict?["description"])
    }

    // MARK: - AddGroupMembersRequest encoding

    func test_addGroupMembersRequest_encodesCustomerIds() throws {
        let req = AddGroupMembersRequest(customerIds: [1, 2, 3])
        let encoder = JSONEncoder()
        let data = try encoder.encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let ids = dict?["customer_ids"] as? [Int]
        XCTAssertEqual(ids, [1, 2, 3])
    }

    // MARK: - CustomerGroupsRepositoryImpl wiring

    func test_repositoryImpl_listGroups_delegatesToApi() async throws {
        let stubApi = GroupStubAPIClient(listResult: .success([.stub(id: 5)]))
        let repo = CustomerGroupsRepositoryImpl(api: stubApi)

        let groups = try await repo.listGroups()

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].id, 5)
    }

    func test_repositoryImpl_deleteGroup_sendsCorrectPath() async throws {
        let stubApi = GroupStubAPIClient()
        let repo = CustomerGroupsRepositoryImpl(api: stubApi)

        try await repo.deleteGroup(id: 7)

        let deletedPath = await stubApi.lastDeletedPath
        XCTAssertEqual(deletedPath, "/api/v1/sms/groups/7")
    }

    func test_repositoryImpl_removeMember_sendsCorrectPath() async throws {
        let stubApi = GroupStubAPIClient()
        let repo = CustomerGroupsRepositoryImpl(api: stubApi)

        try await repo.removeMember(groupId: 3, customerId: 42)

        let deletedPath = await stubApi.lastDeletedPath
        XCTAssertEqual(deletedPath, "/api/v1/sms/groups/3/members/42")
    }

    func test_repositoryImpl_createGroup_sendsToCorrectEndpoint() async throws {
        let newGroup = CustomerGroup.stub(id: 88, name: "New")
        let stubApi = GroupStubAPIClient(createResult: .success(newGroup))
        let repo = CustomerGroupsRepositoryImpl(api: stubApi)

        let req = CreateGroupRequest(name: "New", description: nil, isDynamic: false)
        let created = try await repo.createGroup(req)

        XCTAssertEqual(created.id, 88)
        let postPath = await stubApi.lastPostPath
        XCTAssertEqual(postPath, "/api/v1/sms/groups")
    }

    // MARK: - Helpers

    private func decodeGroup(_ json: String) throws -> CustomerGroup {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CustomerGroup.self, from: Data(json.utf8))
    }

    private func decodeMember(_ json: String) throws -> CustomerGroupMember {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CustomerGroupMember.self, from: Data(json.utf8))
    }
}

// MARK: - GroupStubAPIClient (API-level stub for repository tests)

actor GroupStubAPIClient: APIClient {

    var listResult: Result<[CustomerGroup], Error>
    var createResult: Result<CustomerGroup, Error>

    private(set) var lastDeletedPath: String?
    private(set) var lastPostPath: String?

    init(
        listResult: Result<[CustomerGroup], Error> = .success([]),
        createResult: Result<CustomerGroup, Error> = .success(.stub())
    ) {
        self.listResult = listResult
        self.createResult = createResult
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if path == "/api/v1/sms/groups" {
            // listCustomerGroups() calls get("/api/v1/sms/groups", as: [CustomerGroup].self)
            let groups = try listResult.get()
            guard let cast = groups as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        }
        if path.hasPrefix("/api/v1/sms/groups/") {
            let detail = CustomerGroupDetail.stub()
            guard let cast = detail as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        }
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        lastPostPath = path
        if path == "/api/v1/sms/groups" {
            let group = try createResult.get()
            guard let cast = group as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        }
        if path.hasSuffix("/members") {
            let resp = AddGroupMembersResponse.stub()
            guard let cast = resp as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        }
        throw APITransportError.noBaseURL
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        let group = try createResult.get()
        guard let cast = group as? T else { throw APITransportError.decoding("type mismatch") }
        return cast
    }

    func delete(_ path: String) async throws {
        lastDeletedPath = path
    }

    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.noBaseURL
    }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
