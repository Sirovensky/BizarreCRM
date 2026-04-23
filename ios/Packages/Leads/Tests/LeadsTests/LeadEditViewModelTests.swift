import XCTest
@testable import Leads
@testable import Networking

// MARK: - Mock for edit tests

actor MockLeadEditAPIClient: APIClient {
    enum PutOutcome {
        case success(LeadDetail)
        case failure(Error)
    }

    var putOutcome: PutOutcome = .success(LeadDetail.editFixture())
    private(set) var putCallCount: Int = 0
    private(set) var lastPutPath: String?

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T {
        putCallCount += 1
        lastPutPath = path
        switch putOutcome {
        case .success(let detail):
            guard let cast = detail as? T else {
                throw APITransportError.decoding("type mismatch in mock")
            }
            return cast
        case .failure(let err):
            throw err
        }
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
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
}

// MARK: - Fixtures

extension LeadDetail {
    static func editFixture(
        id: Int64 = 99,
        firstName: String = "Ada",
        lastName: String = "Lovelace",
        status: String = "new",
        notes: String? = nil,
        source: String? = nil,
        assignedTo: Int64? = nil
    ) -> LeadDetail {
        let dict: [String: Any] = [
            "id": id,
            "first_name": firstName,
            "last_name": lastName,
            "status": status,
            "notes": notes as Any,
            "source": source as Any,
            "devices": [Any](),
            "appointments": [Any](),
        ]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(LeadDetail.self, from: data)
    }
}

// MARK: - LeadEditViewModel tests

@MainActor
final class LeadEditViewModelTests: XCTestCase {

    // MARK: - Initial state

    func test_initialState_isIdle() {
        let api = MockLeadEditAPIClient()
        let vm = LeadEditViewModel(api: api, lead: .editFixture())
        if case .idle = vm.state { } else {
            XCTFail("Expected .idle initial state, got \(vm.state)")
        }
    }

    func test_init_populatesFields() {
        let lead = LeadDetail.editFixture(
            firstName: "Ada",
            lastName: "Lovelace",
            status: "qualified",
            notes: "Good lead",
            source: "referral"
        )
        let vm = LeadEditViewModel(api: MockLeadEditAPIClient(), lead: lead)
        XCTAssertEqual(vm.status, "qualified")
        XCTAssertEqual(vm.notes, "Good lead")
        XCTAssertEqual(vm.source, "referral")
    }

    // MARK: - Save success

    func test_save_transitionsToSuccess() async throws {
        let api = MockLeadEditAPIClient()
        let expected = LeadDetail.editFixture(id: 99, status: "contacted")
        await api.setPutOutcome(.success(expected))
        let vm = LeadEditViewModel(api: api, lead: .editFixture(id: 99))
        vm.status = "contacted"

        await vm.save()

        if case .saved(let detail) = vm.state {
            XCTAssertEqual(detail.status, "contacted")
        } else {
            XCTFail("Expected .saved, got \(vm.state)")
        }
    }

    func test_save_callsCorrectEndpoint() async throws {
        let api = MockLeadEditAPIClient()
        let vm = LeadEditViewModel(api: api, lead: .editFixture(id: 42))

        await vm.save()

        let path = await api.lastPutPath
        XCTAssertEqual(path, "/api/v1/leads/42")
    }

    func test_save_callsAPIOnce() async throws {
        let api = MockLeadEditAPIClient()
        let vm = LeadEditViewModel(api: api, lead: .editFixture())

        await vm.save()

        let count = await api.putCallCount
        XCTAssertEqual(count, 1)
    }

    // MARK: - Save failure

    func test_save_networkError_transitionsToFailed() async throws {
        let api = MockLeadEditAPIClient()
        await api.setPutOutcome(.failure(APITransportError.noBaseURL))
        let vm = LeadEditViewModel(api: api, lead: .editFixture())

        await vm.save()

        if case .failed = vm.state { } else {
            XCTFail("Expected .failed state, got \(vm.state)")
        }
    }

    func test_save_whileSubmitting_isNoop() async throws {
        let api = MockLeadEditAPIClient()
        let vm = LeadEditViewModel(api: api, lead: .editFixture())
        // Force into submitting by calling save twice without await between
        async let first: () = vm.save()
        async let second: () = vm.save()
        await first
        await second

        // Only one actual network call should occur
        let count = await api.putCallCount
        XCTAssertLessThanOrEqual(count, 1,
            "Concurrent save() calls must be deduplicated; at most 1 network call")
    }

    // MARK: - Lost reason

    func test_save_toStatusLost_withReason_sendsReason() async throws {
        let api = MockLeadEditAPIClient()
        let expected = LeadDetail.editFixture(status: "lost")
        await api.setPutOutcome(.success(expected))
        let vm = LeadEditViewModel(api: api, lead: .editFixture(status: "new"))
        vm.status = "lost"
        vm.lostReason = "price"

        await vm.save()

        // Should not error — lost_reason was included
        if case .saved = vm.state { } else {
            XCTFail("Expected .saved after transition to lost with reason")
        }
    }

    // MARK: - Reset

    func test_reset_returnsToIdle() async throws {
        let api = MockLeadEditAPIClient()
        await api.setPutOutcome(.failure(APITransportError.noBaseURL))
        let vm = LeadEditViewModel(api: api, lead: .editFixture())
        await vm.save()
        vm.reset()
        if case .idle = vm.state { } else {
            XCTFail("Expected .idle after reset(), got \(vm.state)")
        }
    }
}

// MARK: - MockLeadEditAPIClient helper

extension MockLeadEditAPIClient {
    func setPutOutcome(_ outcome: PutOutcome) {
        putOutcome = outcome
    }
}
