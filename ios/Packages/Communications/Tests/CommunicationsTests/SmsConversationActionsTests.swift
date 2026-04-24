import XCTest
@testable import Communications
@testable import Networking

// MARK: - SmsActionAPIStub
//
// Tracks PATCH calls to flag/pin/read endpoints. Used by
// SmsRepositoryImpl and SmsCachedRepositoryImpl tests.

actor SmsActionAPIStub: APIClient {
    // MARK: Configurable outcomes
    private(set) var markReadCallCount: Int = 0
    private(set) var flagCallCount: Int = 0
    private(set) var pinCallCount: Int = 0
    private(set) var listCallCount: Int = 0

    var markReadError: Error?
    var flagResult: SmsConversationFlagResult?
    var flagError: Error?
    var pinResult: SmsConversationPinResult?
    var pinError: Error?
    var conversations: [SmsConversation] = []

    func setMarkReadError(_ err: Error?) { markReadError = err }
    func setFlagResult(_ r: SmsConversationFlagResult?) { flagResult = r }
    func setFlagError(_ err: Error?) { flagError = err }
    func setPinResult(_ r: SmsConversationPinResult?) { pinResult = r }
    func setPinError(_ err: Error?) { pinError = err }
    func setConversations(_ c: [SmsConversation]) { conversations = c }

    // MARK: APIClient

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if path.contains("/sms/conversations") {
            listCallCount += 1
            let resp = SmsConversationsResponse(conversations: conversations)
            guard let cast = resp as? T else { throw APITransportError.decoding("type") }
            return cast
        }
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if path.hasSuffix("/read") {
            markReadCallCount += 1
            if let err = markReadError { throw err }
            // Server returns { success: true } with no data. `patchVoid` catches
            // `envelopeFailure` so we simulate it here by throwing that error
            // which `patchVoid` will swallow (treated as success on 200).
            throw APITransportError.envelopeFailure(message: nil)
        }
        if path.hasSuffix("/flag") {
            flagCallCount += 1
            if let err = flagError { throw err }
            let phone = extractPhone(path, suffix: "/flag")
            let r = flagResult ?? SmsConversationFlagResult(convPhone: phone, isFlagged: true)
            guard let cast = r as? T else { throw APITransportError.decoding("flag") }
            return cast
        }
        if path.hasSuffix("/pin") {
            pinCallCount += 1
            if let err = pinError { throw err }
            let phone = extractPhone(path, suffix: "/pin")
            let r = pinResult ?? SmsConversationPinResult(convPhone: phone, isPinned: true)
            guard let cast = r as? T else { throw APITransportError.decoding("pin") }
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

    private func extractPhone(_ path: String, suffix: String) -> String {
        path.components(separatedBy: "/conversations/").last?
            .replacingOccurrences(of: suffix, with: "")
            .removingPercentEncoding ?? ""
    }
}

// MARK: - SmsRepositoryImplActionsTests

final class SmsRepositoryImplActionsTests: XCTestCase {

    func test_markRead_callsCorrectEndpoint() async throws {
        let api = SmsActionAPIStub()
        let repo = SmsRepositoryImpl(api: api)

        try await repo.markRead(phone: "+15551234567")

        let count = await api.markReadCallCount
        XCTAssertEqual(count, 1)
    }

    func test_toggleFlag_returnsTrueWhenFlagged() async throws {
        let api = SmsActionAPIStub()
        await api.setFlagResult(SmsConversationFlagResult(convPhone: "+15551234567", isFlagged: true))
        let repo = SmsRepositoryImpl(api: api)

        let result = try await repo.toggleFlag(phone: "+15551234567")

        XCTAssertTrue(result)
        let count = await api.flagCallCount
        XCTAssertEqual(count, 1)
    }

    func test_toggleFlag_returnsFalseWhenUnflagged() async throws {
        let api = SmsActionAPIStub()
        await api.setFlagResult(SmsConversationFlagResult(convPhone: "+15551234567", isFlagged: false))
        let repo = SmsRepositoryImpl(api: api)

        let result = try await repo.toggleFlag(phone: "+15551234567")
        XCTAssertFalse(result)
    }

    func test_togglePin_returnsTrueWhenPinned() async throws {
        let api = SmsActionAPIStub()
        await api.setPinResult(SmsConversationPinResult(convPhone: "+15551234567", isPinned: true))
        let repo = SmsRepositoryImpl(api: api)

        let result = try await repo.togglePin(phone: "+15551234567")
        XCTAssertTrue(result)
    }

    func test_togglePin_returnsFalseWhenUnpinned() async throws {
        let api = SmsActionAPIStub()
        await api.setPinResult(SmsConversationPinResult(convPhone: "+15551234567", isPinned: false))
        let repo = SmsRepositoryImpl(api: api)

        let result = try await repo.togglePin(phone: "+15551234567")
        XCTAssertFalse(result)
    }

    func test_markRead_propagatesError() async throws {
        let api = SmsActionAPIStub()
        await api.setMarkReadError(APITransportError.networkUnavailable)
        let repo = SmsRepositoryImpl(api: api)

        do {
            try await repo.markRead(phone: "+15551234567")
            XCTFail("Expected error")
        } catch { /* correct */ }
    }

    func test_toggleFlag_propagatesError() async throws {
        let api = SmsActionAPIStub()
        await api.setFlagError(APITransportError.networkUnavailable)
        let repo = SmsRepositoryImpl(api: api)

        do {
            _ = try await repo.toggleFlag(phone: "+15551234567")
            XCTFail("Expected error")
        } catch { /* correct */ }
    }

    func test_togglePin_propagatesError() async throws {
        let api = SmsActionAPIStub()
        await api.setPinError(APITransportError.networkUnavailable)
        let repo = SmsRepositoryImpl(api: api)

        do {
            _ = try await repo.togglePin(phone: "+15551234567")
            XCTFail("Expected error")
        } catch { /* correct */ }
    }
}

// MARK: - SmsCachedRepositoryActionsTests

final class SmsCachedRepositoryActionsTests: XCTestCase {

    func test_markRead_invalidatesCache() async throws {
        let api = SmsActionAPIStub()
        await api.setConversations([SmsConversation(convPhone: "+15551234567", unreadCount: 3)])
        let repo = SmsCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        _ = try await repo.listConversations(keyword: nil)    // populates cache
        let before = await api.listCallCount
        XCTAssertEqual(before, 1)

        try await repo.markRead(phone: "+15551234567")        // should invalidate
        _ = try await repo.listConversations(keyword: nil)    // should re-fetch

        let after = await api.listCallCount
        XCTAssertEqual(after, 2, "Cache must be invalidated after markRead")
    }

    func test_toggleFlag_invalidatesCache() async throws {
        let api = SmsActionAPIStub()
        await api.setConversations([SmsConversation(convPhone: "+15551234567")])
        let repo = SmsCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        _ = try await repo.listConversations(keyword: nil)
        _ = try await repo.toggleFlag(phone: "+15551234567")
        _ = try await repo.listConversations(keyword: nil)

        let count = await api.listCallCount
        XCTAssertEqual(count, 2, "Cache must be invalidated after toggleFlag")
    }

    func test_togglePin_invalidatesCache() async throws {
        let api = SmsActionAPIStub()
        await api.setConversations([SmsConversation(convPhone: "+15551234567")])
        let repo = SmsCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        _ = try await repo.listConversations(keyword: nil)
        _ = try await repo.togglePin(phone: "+15551234567")
        _ = try await repo.listConversations(keyword: nil)

        let count = await api.listCallCount
        XCTAssertEqual(count, 2, "Cache must be invalidated after togglePin")
    }

    func test_toggleFlag_returnsFlagValue() async throws {
        let api = SmsActionAPIStub()
        await api.setFlagResult(SmsConversationFlagResult(convPhone: "+15551234567", isFlagged: true))
        let repo = SmsCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        let flagged = try await repo.toggleFlag(phone: "+15551234567")
        XCTAssertTrue(flagged)
    }

    func test_togglePin_returnsPinValue() async throws {
        let api = SmsActionAPIStub()
        await api.setPinResult(SmsConversationPinResult(convPhone: "+15551234567", isPinned: false))
        let repo = SmsCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        let pinned = try await repo.togglePin(phone: "+15551234567")
        XCTAssertFalse(pinned)
    }
}

// MARK: - SmsListViewModelActionsTests

@MainActor
final class SmsListViewModelActionsTests: XCTestCase {

    // MARK: - SmsActionStubRepo (inline for ViewModel tests)

    final actor SmsActionStubRepo: SmsRepository {
        var conversations: [SmsConversation]
        var nextFlagValue: Bool = false
        var nextPinValue: Bool = false
        var markReadError: Error?
        var flagError: Error?
        var pinError: Error?
        private(set) var listCallCount: Int = 0

        init(conversations: [SmsConversation]) {
            self.conversations = conversations
        }

        func setNextFlagValue(_ v: Bool) { nextFlagValue = v }
        func setNextPinValue(_ v: Bool) { nextPinValue = v }
        func setMarkReadError(_ e: Error?) { markReadError = e }
        func setFlagError(_ e: Error?) { flagError = e }
        func setPinError(_ e: Error?) { pinError = e }

        func listConversations(keyword: String?) async throws -> [SmsConversation] {
            listCallCount += 1
            return conversations
        }
        func markRead(phone: String) async throws {
            if let err = markReadError { throw err }
        }
        func toggleFlag(phone: String) async throws -> Bool {
            if let err = flagError { throw err }
            return nextFlagValue
        }
        func togglePin(phone: String) async throws -> Bool {
            if let err = pinError { throw err }
            return nextPinValue
        }
        func toggleArchive(phone: String) async throws -> Bool { false }
    }

    // MARK: - Helpers

    private func makeConv(phone: String, unread: Int = 0, flagged: Bool = false, pinned: Bool = false) -> SmsConversation {
        SmsConversation(convPhone: phone, unreadCount: unread, isFlagged: flagged, isPinned: pinned)
    }

    // MARK: - Mark read

    func test_markRead_zeroesUnreadCount_optimistically() async {
        let stub = SmsActionStubRepo(conversations: [makeConv(phone: "+1555", unread: 5)])
        let vm = SmsListViewModel(repo: stub)
        await vm.load()

        await vm.markRead(phone: "+1555")

        XCTAssertEqual(vm.conversations.first?.unreadCount, 0)
    }

    func test_markRead_setsActionError_onFailure() async {
        let stub = SmsActionStubRepo(conversations: [makeConv(phone: "+1555", unread: 2)])
        await stub.setMarkReadError(APITransportError.networkUnavailable)
        let vm = SmsListViewModel(repo: stub)
        await vm.load()

        await vm.markRead(phone: "+1555")

        XCTAssertNotNil(vm.actionError)
    }

    // MARK: - Flag

    func test_toggleFlag_flipsFlag_toTrue() async {
        let stub = SmsActionStubRepo(conversations: [makeConv(phone: "+1555", flagged: false)])
        await stub.setNextFlagValue(true)
        let vm = SmsListViewModel(repo: stub)
        await vm.load()

        await vm.toggleFlag(phone: "+1555")

        XCTAssertTrue(vm.conversations.first?.isFlagged == true)
    }

    func test_toggleFlag_flipsFlag_toFalse() async {
        let stub = SmsActionStubRepo(conversations: [makeConv(phone: "+1555", flagged: true)])
        await stub.setNextFlagValue(false)
        let vm = SmsListViewModel(repo: stub)
        await vm.load()

        await vm.toggleFlag(phone: "+1555")

        XCTAssertFalse(vm.conversations.first?.isFlagged == true)
    }

    func test_toggleFlag_setsActionError_onFailure() async {
        let stub = SmsActionStubRepo(conversations: [makeConv(phone: "+1555")])
        await stub.setFlagError(APITransportError.networkUnavailable)
        let vm = SmsListViewModel(repo: stub)
        await vm.load()

        await vm.toggleFlag(phone: "+1555")

        XCTAssertNotNil(vm.actionError)
    }

    // MARK: - Pin

    func test_togglePin_flipsPin_andSortsPinnedToTop() async {
        let stub = SmsActionStubRepo(conversations: [
            makeConv(phone: "+1111", pinned: false),
            makeConv(phone: "+2222", pinned: false)
        ])
        await stub.setNextPinValue(true)
        let vm = SmsListViewModel(repo: stub)
        await vm.load()

        await vm.togglePin(phone: "+2222")

        XCTAssertEqual(vm.conversations.first?.convPhone, "+2222")
        XCTAssertTrue(vm.conversations.first?.isPinned == true)
    }

    func test_togglePin_unpin_movesToNormalPosition() async {
        let stub = SmsActionStubRepo(conversations: [
            makeConv(phone: "+1111", pinned: false),
            makeConv(phone: "+2222", pinned: true)
        ])
        await stub.setNextPinValue(false)
        let vm = SmsListViewModel(repo: stub)
        await vm.load()

        await vm.togglePin(phone: "+2222")

        // After unpin the second row is no longer pinned
        let target = vm.conversations.first(where: { $0.convPhone == "+2222" })
        XCTAssertFalse(target?.isPinned == true)
    }

    func test_togglePin_setsActionError_onFailure() async {
        let stub = SmsActionStubRepo(conversations: [makeConv(phone: "+1555")])
        await stub.setPinError(APITransportError.networkUnavailable)
        let vm = SmsListViewModel(repo: stub)
        await vm.load()

        await vm.togglePin(phone: "+1555")

        XCTAssertNotNil(vm.actionError)
    }

    // MARK: - clearActionError

    func test_clearActionError_nilsMessage() async {
        let stub = SmsActionStubRepo(conversations: [makeConv(phone: "+1555")])
        await stub.setFlagError(APITransportError.networkUnavailable)
        let vm = SmsListViewModel(repo: stub)
        await vm.load()
        await vm.toggleFlag(phone: "+1555")
        XCTAssertNotNil(vm.actionError)

        vm.clearActionError()
        XCTAssertNil(vm.actionError)
    }

    // MARK: - Multiple conversations

    func test_markRead_onlyAffectsTargetConversation() async {
        let stub = SmsActionStubRepo(conversations: [
            makeConv(phone: "+1111", unread: 3),
            makeConv(phone: "+2222", unread: 7)
        ])
        let vm = SmsListViewModel(repo: stub)
        await vm.load()

        await vm.markRead(phone: "+1111")

        let conv1 = vm.conversations.first(where: { $0.convPhone == "+1111" })
        let conv2 = vm.conversations.first(where: { $0.convPhone == "+2222" })
        XCTAssertEqual(conv1?.unreadCount, 0, "Only +1111 should be marked read")
        XCTAssertEqual(conv2?.unreadCount, 7, "+2222 should be unchanged")
    }
}
