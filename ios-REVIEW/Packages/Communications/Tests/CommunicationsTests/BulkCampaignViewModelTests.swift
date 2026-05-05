import XCTest
@testable import Communications
@testable import Networking

// MARK: - Mock

actor MockBulkCampaignAPIClient: APIClient {
    enum Outcome { case preview(BulkCampaignPreview); case failure(Error) }
    var previewOutcome: Outcome = .preview(BulkCampaignPreview(recipientCount: 42, optedOutCount: 3, estimatedSegments: 1, tcpaWarning: nil))
    var sendOutcome: Result<BulkCampaignAck, Error> = .success(BulkCampaignAck(campaignId: 1, recipientCount: 42, status: "queued"))

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        switch previewOutcome {
        case .preview(let p):
            guard let cast = p as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        case .failure(let err):
            throw err
        }
    }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        switch sendOutcome {
        case .success(let ack):
            guard let cast = ack as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        case .failure(let err):
            throw err
        }
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

// MARK: - Tests

/// §12.12 — Bulk SMS campaign compose view model tests.
@MainActor
final class BulkCampaignViewModelTests: XCTestCase {

    // MARK: isBodyValid

    func test_emptyBodyIsInvalid() {
        let vm = BulkCampaignViewModel(api: MockBulkCampaignAPIClient())
        vm.body = ""
        XCTAssertFalse(vm.isBodyValid)
    }

    func test_nonEmptyBodyIsValid() {
        let vm = BulkCampaignViewModel(api: MockBulkCampaignAPIClient())
        vm.body = "Hello!"
        XCTAssertTrue(vm.isBodyValid)
    }

    func test_whitespaceOnlyBodyIsInvalid() {
        let vm = BulkCampaignViewModel(api: MockBulkCampaignAPIClient())
        vm.body = "   "
        XCTAssertFalse(vm.isBodyValid)
    }

    // MARK: smsSegments

    func test_160CharsIsOneSegment() {
        let vm = BulkCampaignViewModel(api: MockBulkCampaignAPIClient())
        vm.body = String(repeating: "a", count: 160)
        XCTAssertEqual(vm.smsSegments, 1)
    }

    func test_161CharsIsTwoSegments() {
        let vm = BulkCampaignViewModel(api: MockBulkCampaignAPIClient())
        vm.body = String(repeating: "a", count: 161)
        XCTAssertEqual(vm.smsSegments, 2)
    }

    // MARK: charCount

    func test_charCountMatchesBodyLength() {
        let vm = BulkCampaignViewModel(api: MockBulkCampaignAPIClient())
        vm.body = "Hello, world!"
        XCTAssertEqual(vm.charCount, 13)
    }

    // MARK: preview

    func test_previewWithEmptyBodyMovesToFailed() async {
        let vm = BulkCampaignViewModel(api: MockBulkCampaignAPIClient())
        vm.body = ""
        await vm.preview()
        if case .failed = vm.step { } else { XCTFail("Expected .failed state") }
    }

    func test_previewWithValidBodyMovesToConfirmSend() async {
        let vm = BulkCampaignViewModel(api: MockBulkCampaignAPIClient())
        vm.body = "Your repair is ready!"
        await vm.preview()
        if case .confirmSend(let p) = vm.step {
            XCTAssertEqual(p.recipientCount, 42)
        } else {
            XCTFail("Expected .confirmSend state, got \(vm.step)")
        }
    }

    // MARK: send

    func test_sendMovesToDone() async {
        let api = MockBulkCampaignAPIClient()
        let vm = BulkCampaignViewModel(api: api)
        vm.body = "Your order is ready."
        await vm.send()
        if case .done(let ack) = vm.step {
            XCTAssertEqual(ack.campaignId, 1)
            XCTAssertEqual(ack.status, "queued")
        } else {
            XCTFail("Expected .done state, got \(vm.step)")
        }
    }

    func test_sendFailureMovesToFailedState() async {
        let api = MockBulkCampaignAPIClient()
        await api.run { $0.sendOutcome = .failure(URLError(.badServerResponse)) }
        let vm = BulkCampaignViewModel(api: api)
        vm.body = "Test"
        await vm.send()
        if case .failed = vm.step { } else { XCTFail("Expected .failed") }
    }

    // MARK: segmentKey

    func test_segmentKeyMatchesRawValue() {
        let vm = BulkCampaignViewModel(api: MockBulkCampaignAPIClient())
        vm.selectedSegment = .lapsed
        XCTAssertEqual(vm.segmentKey, "lapsed")
    }

    // MARK: restart

    func test_restartClearsState() {
        let vm = BulkCampaignViewModel(api: MockBulkCampaignAPIClient())
        vm.body = "Some body"
        vm.selectedSegment = .loyaltyMembers
        vm.restart()
        XCTAssertEqual(vm.body, "")
        XCTAssertEqual(vm.selectedSegment, .all)
        if case .compose = vm.step { } else { XCTFail("Expected .compose") }
    }

    // MARK: BulkCampaignSegment

    func test_allSegmentsHaveNonEmptyDisplayNames() {
        for seg in BulkCampaignSegment.allCases {
            XCTAssertFalse(seg.displayName.isEmpty, "displayName empty for \(seg.rawValue)")
            XCTAssertFalse(seg.systemIcon.isEmpty, "systemIcon empty for \(seg.rawValue)")
        }
    }
}

// MARK: - Actor helper

private extension MockBulkCampaignAPIClient {
    func run(_ block: (inout MockBulkCampaignAPIClient) -> Void) {}
}

// Workaround for actor mutation in tests
extension MockBulkCampaignAPIClient {
    func setSendOutcome(_ outcome: Result<BulkCampaignAck, Error>) {
        sendOutcome = outcome
    }
}
