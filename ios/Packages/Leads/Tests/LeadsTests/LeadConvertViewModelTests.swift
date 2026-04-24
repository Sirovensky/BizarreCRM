import XCTest
@testable import Leads
@testable import Networking

// MARK: - Mock for convert tests

actor MockConvertAPIClient: APIClient {
    enum PostOutcome {
        case success(LeadConvertResponse)
        case failure(Error)
    }

    var postOutcome: PostOutcome
    private(set) var postCallCount = 0
    private(set) var lastPostPath: String?

    init(outcome: PostOutcome = .success(.fixture())) {
        self.postOutcome = outcome
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T {
        postCallCount += 1
        lastPostPath = path
        switch postOutcome {
        case .success(let response):
            guard let cast = response as? T else {
                throw APITransportError.decoding("type mismatch in MockConvertAPIClient")
            }
            return cast
        case .failure(let err):
            throw err
        }
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func delete(_ path: String) async throws { throw APITransportError.noBaseURL }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.noBaseURL
    }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}

    func setOutcome(_ outcome: PostOutcome) {
        postOutcome = outcome
    }
}

// MARK: - LeadConvertResponse fixture

extension LeadConvertResponse {
    /// Builds a realistic fixture matching actual server shape:
    /// `{ ticket: { id, order_id, customer_id }, message }`.
    static func fixture(ticketId: Int64 = 777, customerId: Int64 = 42) -> LeadConvertResponse {
        let dict: [String: Any] = [
            "ticket": [
                "id": ticketId,
                "order_id": "T-0777",
                "customer_id": customerId,
            ] as [String: Any],
            "message": "Lead converted to ticket",
        ]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(LeadConvertResponse.self, from: data)
    }
}

// MARK: - LeadConvertViewModelTests

@MainActor
final class LeadConvertViewModelTests: XCTestCase {

    // MARK: - Initial state

    func test_initialState_isIdle() {
        let vm = LeadConvertViewModel(api: MockConvertAPIClient(), leadId: 1)
        if case .idle = vm.state { } else {
            XCTFail("Expected .idle, got \(vm.state)")
        }
    }

    func test_initialCreateTicket_isFalse() {
        let vm = LeadConvertViewModel(api: MockConvertAPIClient(), leadId: 1)
        XCTAssertFalse(vm.createTicket)
    }

    // MARK: - Success path

    func test_convert_success_transitionsToSuccess() async {
        let api = MockConvertAPIClient(outcome: .success(.fixture(ticketId: 123)))
        let vm = LeadConvertViewModel(api: api, leadId: 5)

        await vm.convert()

        if case .success(let tId, _) = vm.state {
            XCTAssertEqual(tId, 123)
        } else {
            XCTFail("Expected .success(ticketId:), got \(vm.state)")
        }
    }

    func test_convert_success_propagatesCustomerId() async {
        let api = MockConvertAPIClient(outcome: .success(.fixture(ticketId: 1, customerId: 99)))
        let vm = LeadConvertViewModel(api: api, leadId: 5)

        await vm.convert()

        if case .success(_, let cId) = vm.state {
            XCTAssertEqual(cId, 99)
        } else {
            XCTFail("Expected .success(_, customerId:), got \(vm.state)")
        }
    }

    func test_convert_callsCorrectEndpoint() async {
        let api = MockConvertAPIClient()
        let vm = LeadConvertViewModel(api: api, leadId: 42)

        await vm.convert()

        let path = await api.lastPostPath
        XCTAssertEqual(path, "/api/v1/leads/42/convert")
    }

    func test_convert_callsAPIOnce() async {
        let api = MockConvertAPIClient()
        let vm = LeadConvertViewModel(api: api, leadId: 1)

        await vm.convert()

        let count = await api.postCallCount
        XCTAssertEqual(count, 1)
    }

    // MARK: - Guard double-tap

    func test_convert_whileSubmitting_isNoop() async {
        let api = MockConvertAPIClient()
        let vm = LeadConvertViewModel(api: api, leadId: 1)

        async let first: () = vm.convert()
        async let second: () = vm.convert()
        await first
        await second

        let count = await api.postCallCount
        XCTAssertLessThanOrEqual(count, 1,
            "Concurrent convert() calls must be deduplicated; at most 1 network call")
    }

    // MARK: - Failure path

    func test_convert_networkError_transitionsToFailed() async {
        let api = MockConvertAPIClient(outcome: .failure(APITransportError.noBaseURL))
        let vm = LeadConvertViewModel(api: api, leadId: 1)

        await vm.convert()

        if case .failed = vm.state { } else {
            XCTFail("Expected .failed, got \(vm.state)")
        }
    }

    func test_convert_failure_includesErrorMessage() async {
        struct SentinelError: Error, LocalizedError {
            var errorDescription: String? { "sentinel error message" }
        }
        let api = MockConvertAPIClient(outcome: .failure(SentinelError()))
        let vm = LeadConvertViewModel(api: api, leadId: 1)

        await vm.convert()

        if case .failed(let msg) = vm.state {
            XCTAssertTrue(msg.contains("sentinel"), "Error message should include underlying reason")
        } else {
            XCTFail("Expected .failed, got \(vm.state)")
        }
    }

    // MARK: - Reset

    func test_reset_fromFailed_returnsIdle() async {
        let api = MockConvertAPIClient(outcome: .failure(APITransportError.noBaseURL))
        let vm = LeadConvertViewModel(api: api, leadId: 1)
        await vm.convert()
        vm.reset()
        if case .idle = vm.state { } else {
            XCTFail("Expected .idle after reset(), got \(vm.state)")
        }
    }

    // MARK: - Response decoding

    func test_convertResponse_decodesTicketId() throws {
        let response = LeadConvertResponse.fixture(ticketId: 999, customerId: 7)
        XCTAssertEqual(response.ticketId, 999)
    }

    func test_convertResponse_decodesCustomerId() throws {
        let response = LeadConvertResponse.fixture(ticketId: 1, customerId: 55)
        XCTAssertEqual(response.customerId, 55)
    }

    func test_convertResponse_decodesMessage() throws {
        let response = LeadConvertResponse.fixture()
        XCTAssertEqual(response.message, "Lead converted to ticket")
    }

    // MARK: - LeadUpdateBody encoding

    func test_leadUpdateBody_onlyEncodesProvidedFields() throws {
        let body = LeadUpdateBody(status: "contacted")
        let data = try JSONEncoder().encode(body)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(dict["status"] as? String, "contacted")
        XCTAssertNil(dict["notes"], "notes was not provided; must be absent from JSON")
        XCTAssertNil(dict["assigned_to"], "assigned_to was not provided; must be absent from JSON")
    }

    func test_leadUpdateBody_encodesLostReason() throws {
        let body = LeadUpdateBody(status: "lost", lostReason: "price")
        let data = try JSONEncoder().encode(body)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(dict["lost_reason"] as? String, "price")
    }

    func test_leadUpdateBody_encodesAssignedTo() throws {
        let body = LeadUpdateBody(assignedTo: 7)
        let data = try JSONEncoder().encode(body)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(dict["assigned_to"] as? Int, 7)
    }
}
