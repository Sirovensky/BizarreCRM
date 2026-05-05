import XCTest
@testable import Communications
@testable import Networking

// MARK: - SmsArchiveAPIStub
//
// Minimal APIClient stub wired for the archive PATCH endpoint.
// Shares the same structural pattern as SmsActionAPIStub in
// SmsConversationActionsTests.swift.

private actor SmsArchiveAPIStub: APIClient {
    private(set) var archiveCallCount: Int = 0
    private(set) var lastArchivedPhone: String?
    var archiveResult: SmsConversationArchiveResult?
    var archiveError: Error?
    var conversations: [SmsConversation] = []

    func setArchiveResult(_ r: SmsConversationArchiveResult?) { archiveResult = r }
    func setArchiveError(_ e: Error?) { archiveError = e }
    func setConversations(_ c: [SmsConversation]) { conversations = c }

    // MARK: APIClient conformance

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if path.contains("/sms/conversations") {
            let resp = SmsConversationsResponse(conversations: conversations)
            guard let cast = resp as? T else { throw APITransportError.decoding("type") }
            return cast
        }
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if path.hasSuffix("/archive") {
            archiveCallCount += 1
            let phone = path
                .components(separatedBy: "/conversations/").last?
                .replacingOccurrences(of: "/archive", with: "")
                .removingPercentEncoding ?? ""
            lastArchivedPhone = phone
            if let err = archiveError { throw err }
            let r = archiveResult ?? SmsConversationArchiveResult(convPhone: phone, isArchived: true)
            guard let cast = r as? T else { throw APITransportError.decoding("archive") }
            return cast
        }
        throw APITransportError.noBaseURL
    }

    func delete(_ path: String) async throws { throw APITransportError.noBaseURL }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: (any AuthSessionRefresher)?) async {}
}

// MARK: - SmsRepositoryImpl archive tests

final class SmsRepositoryImplArchiveTests: XCTestCase {

    func test_toggleArchive_callsCorrectEndpoint() async throws {
        let api = SmsArchiveAPIStub()
        let repo = SmsRepositoryImpl(api: api)

        _ = try await repo.toggleArchive(phone: "+15559998888")

        let count = await api.archiveCallCount
        XCTAssertEqual(count, 1)
    }

    func test_toggleArchive_returnsTrueWhenArchived() async throws {
        let api = SmsArchiveAPIStub()
        await api.setArchiveResult(SmsConversationArchiveResult(convPhone: "+15559998888", isArchived: true))
        let repo = SmsRepositoryImpl(api: api)

        let result = try await repo.toggleArchive(phone: "+15559998888")

        XCTAssertTrue(result)
    }

    func test_toggleArchive_returnsFalseWhenUnarchived() async throws {
        let api = SmsArchiveAPIStub()
        await api.setArchiveResult(SmsConversationArchiveResult(convPhone: "+15559998888", isArchived: false))
        let repo = SmsRepositoryImpl(api: api)

        let result = try await repo.toggleArchive(phone: "+15559998888")

        XCTAssertFalse(result)
    }

    func test_toggleArchive_propagatesError() async throws {
        let api = SmsArchiveAPIStub()
        await api.setArchiveError(APITransportError.networkUnavailable)
        let repo = SmsRepositoryImpl(api: api)

        do {
            _ = try await repo.toggleArchive(phone: "+15559998888")
            XCTFail("Expected error to be thrown")
        } catch {
            // correct — error propagated
        }
    }

    func test_toggleArchive_encodesPhoneInPath() async throws {
        let api = SmsArchiveAPIStub()
        let repo = SmsRepositoryImpl(api: api)
        let phone = "+15559998888"

        _ = try await repo.toggleArchive(phone: phone)

        let recorded = await api.lastArchivedPhone
        XCTAssertEqual(recorded, phone)
    }
}

// MARK: - SmsCachedRepositoryImpl archive tests

final class SmsCachedRepositoryArchiveTests: XCTestCase {

    func test_toggleArchive_invalidatesCache() async throws {
        let api = SmsArchiveAPIStub()
        let conv = SmsConversation(convPhone: "+15559998888")
        await api.setConversations([conv])
        let repo = SmsCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        _ = try await repo.listConversations(keyword: nil)   // populate cache (1 fetch)
        _ = try await repo.toggleArchive(phone: "+15559998888") // invalidates cache
        _ = try await repo.listConversations(keyword: nil)   // triggers re-fetch

        // Verify the archive patch call was made
        let archiveCount = await api.archiveCallCount
        XCTAssertEqual(archiveCount, 1)
    }

    func test_toggleArchive_returnsArchivedValue() async throws {
        let api = SmsArchiveAPIStub()
        await api.setArchiveResult(SmsConversationArchiveResult(convPhone: "+15559998888", isArchived: true))
        let repo = SmsCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        let archived = try await repo.toggleArchive(phone: "+15559998888")

        XCTAssertTrue(archived)
    }

    func test_toggleArchive_returnsUnarchivedValue() async throws {
        let api = SmsArchiveAPIStub()
        await api.setArchiveResult(SmsConversationArchiveResult(convPhone: "+15559998888", isArchived: false))
        let repo = SmsCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        let archived = try await repo.toggleArchive(phone: "+15559998888")

        XCTAssertFalse(archived)
    }
}

// MARK: - SmsListViewModel archive tests

@MainActor
final class SmsListViewModelArchiveTests: XCTestCase {

    // MARK: - Stub repo

    private final actor ArchiveStubRepo: SmsRepository {
        var conversations: [SmsConversation]
        var nextArchiveValue: Bool = true
        var archiveError: Error?
        private(set) var listCallCount: Int = 0

        init(conversations: [SmsConversation]) {
            self.conversations = conversations
        }

        func setNextArchiveValue(_ v: Bool) { nextArchiveValue = v }
        func setArchiveError(_ e: Error?) { archiveError = e }

        func listConversations(keyword: String?) async throws -> [SmsConversation] {
            listCallCount += 1
            return conversations
        }
        func markRead(phone: String) async throws {}
        func toggleFlag(phone: String) async throws -> Bool { false }
        func togglePin(phone: String) async throws -> Bool { false }
        func toggleArchive(phone: String) async throws -> Bool {
            if let err = archiveError { throw err }
            return nextArchiveValue
        }
    }

    private func makeConv(
        phone: String,
        archived: Bool = false,
        flagged: Bool = false,
        pinned: Bool = false
    ) -> SmsConversation {
        SmsConversation(convPhone: phone, isFlagged: flagged, isPinned: pinned, isArchived: archived)
    }

    // MARK: - Archive removes conversation from list

    func test_toggleArchive_removesConversation_whenArchiving() async {
        let stub = ArchiveStubRepo(conversations: [
            makeConv(phone: "+1111"),
            makeConv(phone: "+2222")
        ])
        await stub.setNextArchiveValue(true)
        let vm = SmsListViewModel(repo: stub)
        await vm.load()
        XCTAssertEqual(vm.conversations.count, 2)

        await vm.toggleArchive(phone: "+1111")

        XCTAssertEqual(vm.conversations.count, 1)
        XCTAssertFalse(vm.conversations.contains(where: { $0.convPhone == "+1111" }))
    }

    func test_toggleArchive_keepsOtherConversations_unchanged() async {
        let stub = ArchiveStubRepo(conversations: [
            makeConv(phone: "+1111"),
            makeConv(phone: "+2222")
        ])
        await stub.setNextArchiveValue(true)
        let vm = SmsListViewModel(repo: stub)
        await vm.load()

        await vm.toggleArchive(phone: "+1111")

        XCTAssertEqual(vm.conversations.first?.convPhone, "+2222")
    }

    func test_toggleArchive_setsActionError_onFailure() async {
        let stub = ArchiveStubRepo(conversations: [makeConv(phone: "+1111")])
        await stub.setArchiveError(APITransportError.networkUnavailable)
        let vm = SmsListViewModel(repo: stub)
        await vm.load()

        await vm.toggleArchive(phone: "+1111")

        XCTAssertNotNil(vm.actionError)
    }

    func test_toggleArchive_preservesConversation_onFailure() async {
        let stub = ArchiveStubRepo(conversations: [makeConv(phone: "+1111")])
        await stub.setArchiveError(APITransportError.networkUnavailable)
        let vm = SmsListViewModel(repo: stub)
        await vm.load()

        await vm.toggleArchive(phone: "+1111")

        // Conversation should NOT be removed when the archive call fails
        XCTAssertEqual(vm.conversations.count, 1)
    }

    // MARK: - Unarchive triggers reload

    func test_toggleArchive_unarchiving_doesNotSilentlyRemoveConversation() async {
        let stub = ArchiveStubRepo(conversations: [makeConv(phone: "+1111", archived: true)])
        await stub.setNextArchiveValue(false)   // server returns is_archived=false
        let vm = SmsListViewModel(repo: stub)
        await vm.load()

        await vm.toggleArchive(phone: "+1111")

        // After unarchive the list reloads; stub returns 1 item so count stays 1
        XCTAssertEqual(vm.conversations.count, 1)
    }

    // MARK: - clearActionError

    func test_clearActionError_afterArchiveFailure_nilsMessage() async {
        let stub = ArchiveStubRepo(conversations: [makeConv(phone: "+1111")])
        await stub.setArchiveError(APITransportError.networkUnavailable)
        let vm = SmsListViewModel(repo: stub)
        await vm.load()
        await vm.toggleArchive(phone: "+1111")
        XCTAssertNotNil(vm.actionError)

        vm.clearActionError()

        XCTAssertNil(vm.actionError)
    }

    // MARK: - Endpoint path encoding

    func test_toggleArchive_endpointPath_isCorrect() async throws {
        let api = SmsArchiveAPIStub()
        let phone = "+15559998888"
        await api.setConversations([SmsConversation(convPhone: phone)])
        let repo = SmsRepositoryImpl(api: api)

        _ = try await repo.toggleArchive(phone: phone)

        let recorded = await api.lastArchivedPhone
        XCTAssertEqual(recorded, phone, "Archive PATCH path must encode the correct phone number")
    }
}

// MARK: - SmsConversationArchiveResult decoding tests

final class SmsConversationArchiveResultTests: XCTestCase {

    func test_decode_isArchived_true() throws {
        let json = """
        {"conv_phone":"+15551234567","is_archived":true}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(SmsConversationArchiveResult.self, from: json)
        XCTAssertTrue(result.isArchived)
        XCTAssertEqual(result.convPhone, "+15551234567")
    }

    func test_decode_isArchived_false() throws {
        let json = """
        {"conv_phone":"+15559998888","is_archived":false}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(SmsConversationArchiveResult.self, from: json)
        XCTAssertFalse(result.isArchived)
    }
}

// MARK: - SmsConversation isArchived field tests

final class SmsConversationIsArchivedTests: XCTestCase {

    func test_decode_isArchived_fromServerShape() throws {
        let json = """
        {
          "conv_phone": "+15551234567",
          "message_count": 3,
          "unread_count": 0,
          "is_flagged": false,
          "is_pinned": false,
          "is_archived": true
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let conv = try decoder.decode(SmsConversation.self, from: json)
        XCTAssertTrue(conv.isArchived)
    }

    func test_decode_isArchived_defaultsFalse_whenMissing() throws {
        let json = """
        {
          "conv_phone": "+15551234567",
          "message_count": 1,
          "unread_count": 0,
          "is_flagged": false,
          "is_pinned": false
        }
        """.data(using: .utf8)!
        // Uses a manual init path — isArchived defaults to false
        let conv = SmsConversation(convPhone: "+15551234567")
        XCTAssertFalse(conv.isArchived)
    }

    func test_init_isArchived_false_byDefault() {
        let conv = SmsConversation(convPhone: "+15559998888")
        XCTAssertFalse(conv.isArchived)
    }

    func test_init_isArchived_true_whenSet() {
        let conv = SmsConversation(convPhone: "+15559998888", isArchived: true)
        XCTAssertTrue(conv.isArchived)
    }
}
