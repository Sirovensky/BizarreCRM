import XCTest
@testable import Communications
@testable import Networking

// MARK: - SmsScheduleSendTests
// §12.2 Schedule send + compliance footer tests.

@MainActor
final class SmsScheduleSendTests: XCTestCase {

    // MARK: - Compliance footer

    func testComplianceFooterAppendedToOutboundMessage() async {
        let mock = MockThreadAPIClient()
        let repo = SmsThreadRepositoryImpl(api: mock)
        let vm = SmsThreadViewModel(repo: repo, phoneNumber: "+10005550000")
        vm.draft = "Hello!"
        vm.appendComplianceFooter = true
        await vm.send()
        // The mock captures the last message sent; it should contain the STOP opt-out.
        XCTAssertTrue(mock.lastSentMessage?.contains("Reply STOP") == true,
                      "Compliance footer must be appended when flag is set")
    }

    func testComplianceFooterNotAppendedWhenDisabled() async {
        let mock = MockThreadAPIClient()
        let repo = SmsThreadRepositoryImpl(api: mock)
        let vm = SmsThreadViewModel(repo: repo, phoneNumber: "+10005550000")
        vm.draft = "Hello!"
        vm.appendComplianceFooter = false
        await vm.send()
        XCTAssertFalse(mock.lastSentMessage?.contains("STOP") == true,
                       "Compliance footer must NOT be appended when flag is off")
    }

    // MARK: - Scheduled send

    func testScheduledSendCallsScheduledEndpoint() async {
        let mock = MockThreadAPIClient()
        let repo = SmsThreadRepositoryImpl(api: mock)
        let vm = SmsThreadViewModel(repo: repo, phoneNumber: "+10005550000")
        vm.draft = "Reminder!"
        vm.scheduledSendAt = Date().addingTimeInterval(3600) // 1 hour from now
        await vm.send()
        XCTAssertTrue(mock.scheduledSendCalled,
                      "Scheduled send should call sendScheduled endpoint")
        XCTAssertFalse(mock.immediateSendCalled,
                       "Immediate send should NOT be called for scheduled messages")
    }

    func testImmediateSendWhenNoScheduleDate() async {
        let mock = MockThreadAPIClient()
        let repo = SmsThreadRepositoryImpl(api: mock)
        let vm = SmsThreadViewModel(repo: repo, phoneNumber: "+10005550000")
        vm.draft = "Hello!"
        vm.scheduledSendAt = nil
        await vm.send()
        XCTAssertTrue(mock.immediateSendCalled,
                      "Immediate send should be used when no schedule date")
        XCTAssertFalse(mock.scheduledSendCalled,
                       "Scheduled send should NOT be called for immediate messages")
    }

    // MARK: - Schedule clears after send

    func testScheduledDateClearsAfterSend() async {
        let mock = MockThreadAPIClient()
        let repo = SmsThreadRepositoryImpl(api: mock)
        let vm = SmsThreadViewModel(repo: repo, phoneNumber: "+10005550000")
        vm.draft = "Reminder!"
        vm.scheduledSendAt = Date().addingTimeInterval(3600)
        await vm.send()
        XCTAssertNil(vm.scheduledSendAt, "scheduledSendAt must be cleared after successful send")
    }

    // MARK: - Draft clears after send

    func testDraftClearsAfterImmediateSend() async {
        let mock = MockThreadAPIClient()
        let repo = SmsThreadRepositoryImpl(api: mock)
        let vm = SmsThreadViewModel(repo: repo, phoneNumber: "+10005550000")
        vm.draft = "Hello!"
        await vm.send()
        XCTAssertTrue(vm.draft.isEmpty, "Draft should clear after successful send")
    }
}

// MARK: - Mock thread API client

private actor MockThreadAPIClient: APIClient {
    private(set) var lastSentMessage: String?
    private(set) var immediateSendCalled: Bool = false
    private(set) var scheduledSendCalled: Bool = false

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        // Return a minimal SmsThread for load() calls.
        if path.contains("/api/v1/sms/conversations") {
            let threadData = try! JSONSerialization.data(withJSONObject: ["messages": [], "customer": NSNull()])
            let thread = try! JSONDecoder().decode(SmsThread.self, from: threadData)
            guard let cast = thread as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        }
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if path == "/api/v1/sms/send" {
            // Capture the message body.
            if let req = body as? SmsSendRequest {
                lastSentMessage = req.message
                immediateSendCalled = true
            } else if let req = body as? SmsSendScheduledRequest {
                lastSentMessage = req.message
                scheduledSendCalled = true
            }
            let msgData = try! JSONSerialization.data(withJSONObject: [
                "id": 1, "direction": "outbound", "status": "sent"
            ])
            let msg = try! JSONDecoder().decode(SmsMessage.self, from: msgData)
            guard let cast = msg as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        }
        throw APITransportError.noBaseURL
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
