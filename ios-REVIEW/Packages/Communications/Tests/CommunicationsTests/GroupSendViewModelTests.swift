import XCTest
@testable import Communications
@testable import Networking

// MARK: - Mock

actor MockGroupSendAPIClient: APIClient {
    enum Outcome { case success, failure(Error) }
    var outcome: Outcome = .success
    private(set) var callCount: Int = 0
    private(set) var lastBody: GroupSendRequest?

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        callCount += 1
        if let b = body as? GroupSendRequest { lastBody = b }
        switch outcome {
        case .success:
            let ack = GroupSendAck(queued: callCount, failed: 0)
            guard let cast = ack as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        case .failure(let err):
            throw err
        }
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws { throw APITransportError.noBaseURL }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

// MARK: - Tests

@MainActor
final class GroupSendViewModelTests: XCTestCase {

    func test_initialState() {
        let api = MockGroupSendAPIClient()
        let vm = GroupSendViewModel(api: api)
        XCTAssertEqual(vm.recipients, [])
        XCTAssertEqual(vm.body, "")
        XCTAssertFalse(vm.isSending)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.progress, 0.0)
    }

    func test_cannotSend_whenNoRecipients() {
        let api = MockGroupSendAPIClient()
        let vm = GroupSendViewModel(api: api)
        vm.body = "Hello!"
        XCTAssertFalse(vm.canSend)
    }

    func test_cannotSend_whenBodyEmpty() {
        let api = MockGroupSendAPIClient()
        let vm = GroupSendViewModel(api: api)
        vm.recipients = ["+15555550001"]
        vm.body = ""
        XCTAssertFalse(vm.canSend)
    }

    func test_canSend_whenRecipientsAndBodyPresent() {
        let api = MockGroupSendAPIClient()
        let vm = GroupSendViewModel(api: api)
        vm.recipients = ["+15555550001", "+15555550002"]
        vm.body = "Hello everyone!"
        XCTAssertTrue(vm.canSend)
    }

    func test_addRecipient_addsUnique() {
        let api = MockGroupSendAPIClient()
        let vm = GroupSendViewModel(api: api)
        vm.addRecipient("+15555550001")
        vm.addRecipient("+15555550001") // duplicate
        XCTAssertEqual(vm.recipients.count, 1)
    }

    func test_removeRecipient() {
        let api = MockGroupSendAPIClient()
        let vm = GroupSendViewModel(api: api)
        vm.addRecipient("+15555550001")
        vm.addRecipient("+15555550002")
        vm.removeRecipient("+15555550001")
        XCTAssertEqual(vm.recipients, ["+15555550002"])
    }

    func test_send_success_setsProgress1AndClears() async {
        let api = MockGroupSendAPIClient()
        let vm = GroupSendViewModel(api: api)
        vm.recipients = ["+15555550001"]
        vm.body = "Hi!"

        await vm.send()

        let count = await api.callCount
        XCTAssertEqual(count, 1)
        XCTAssertFalse(vm.isSending)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.progress, 1.0, accuracy: 0.001)
        XCTAssertTrue(vm.didSend)
    }

    func test_send_failure_setsErrorMessage() async {
        let api = MockGroupSendAPIClient()
        await api.set(.failure(APITransportError.noBaseURL))
        let vm = GroupSendViewModel(api: api)
        vm.recipients = ["+15555550001"]
        vm.body = "Hi!"

        await vm.send()

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.didSend)
    }

    func test_recipientCount_label() {
        let api = MockGroupSendAPIClient()
        let vm = GroupSendViewModel(api: api)
        vm.recipients = ["+1", "+2", "+3"]
        XCTAssertEqual(vm.recipientCountLabel, "3 recipients")
    }
}

extension MockGroupSendAPIClient {
    func set(_ o: Outcome) { outcome = o }
}
