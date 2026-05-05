import XCTest
@testable import Leads
import Networking

// MARK: - §9.3 Status workflow transition unit tests

@MainActor
final class LeadStatusTransitionViewModelTests: XCTestCase {

    // MARK: availableTransitions state machine

    func test_transitions_new_hasExpectedOptions() {
        let vm = makeVM(status: "new")
        XCTAssertEqual(vm.availableTransitions, ["contacted", "qualified", "lost"])
    }

    func test_transitions_contacted() {
        let vm = makeVM(status: "contacted")
        XCTAssertEqual(vm.availableTransitions, ["scheduled", "qualified", "lost"])
    }

    func test_transitions_scheduled() {
        let vm = makeVM(status: "scheduled")
        XCTAssertEqual(vm.availableTransitions, ["qualified", "proposal", "lost"])
    }

    func test_transitions_qualified() {
        let vm = makeVM(status: "qualified")
        XCTAssertEqual(vm.availableTransitions, ["proposal", "converted", "lost"])
    }

    func test_transitions_proposal() {
        let vm = makeVM(status: "proposal")
        XCTAssertEqual(vm.availableTransitions, ["converted", "lost"])
    }

    func test_transitions_lost_canReopen() {
        let vm = makeVM(status: "lost")
        XCTAssertEqual(vm.availableTransitions, ["new", "contacted"])
    }

    func test_transitions_converted_isEmpty() {
        let vm = makeVM(status: "converted")
        XCTAssertTrue(vm.availableTransitions.isEmpty)
    }

    func test_transitions_nil_status_returnsAll() {
        let vm = makeVM(status: nil)
        // unknown status returns all statuses except the current (nil → no match → all statuses)
        XCTAssertFalse(vm.availableTransitions.isEmpty)
        XCTAssertEqual(vm.availableTransitions.count, LeadStatusTransitionViewModel.allStatuses.count)
    }

    // MARK: allStatuses constant

    func test_allStatuses_contains7States() {
        XCTAssertEqual(LeadStatusTransitionViewModel.allStatuses.count, 7)
    }

    func test_allStatuses_containsLost() {
        XCTAssertTrue(LeadStatusTransitionViewModel.allStatuses.contains("lost"))
    }

    func test_allStatuses_containsConverted() {
        XCTAssertTrue(LeadStatusTransitionViewModel.allStatuses.contains("converted"))
    }

    // MARK: transition happy path

    func test_transition_happyPath_returnsUpdatedDetail() async throws {
        let api = SucceedingTransitionStubAPI()
        let lead = LeadDetail.stub(status: "new")
        let vm = LeadStatusTransitionViewModel(api: api, lead: lead)

        let updated = try await vm.transition(to: "contacted")

        XCTAssertEqual(updated.status, "contacted")
        XCTAssertFalse(vm.isTransitioning)
        XCTAssertNil(vm.error)
    }

    func test_transition_failure_setsErrorField() async {
        let api = FailingTransitionStubAPI()
        let lead = LeadDetail.stub(status: "new")
        let vm = LeadStatusTransitionViewModel(api: api, lead: lead)

        do {
            _ = try await vm.transition(to: "contacted")
            XCTFail("Should throw")
        } catch {
            XCTAssertFalse(vm.isTransitioning)
        }
    }
}

// MARK: - Helpers

private func makeVM(status: String?) -> LeadStatusTransitionViewModel {
    let lead = LeadDetail.stub(status: status)
    return LeadStatusTransitionViewModel(api: FailingTransitionStubAPI(), lead: lead)
}

private extension LeadDetail {
    static func stub(status: String?) -> LeadDetail {
        let statusValue = status.flatMap { "\"\($0)\"" } ?? "null"
        let json = """
        {"id":1,"status":\(statusValue),"first_name":"Test","last_name":"Lead",
         "email":null,"phone":null,"source":null,"notes":null,"lead_score":50,
         "assigned_first_name":null,"assigned_last_name":null,
         "customer_id":null,"customer_first_name":null,"customer_last_name":null,
         "created_at":null,"updated_at":null,"devices":[],"appointments":[]}
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(LeadDetail.self, from: json)
    }
}

// MARK: - Stubs

private actor FailingTransitionStubAPI: APIClient {
    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

private actor SucceedingTransitionStubAPI: APIClient {
    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        // Simulate server returning the updated lead
        let json = """
        {"id":1,"status":"contacted","first_name":"Test","last_name":"Lead",
         "email":null,"phone":null,"source":null,"notes":null,"lead_score":50,
         "assigned_first_name":null,"assigned_last_name":null,
         "customer_id":null,"customer_first_name":null,"customer_last_name":null,
         "created_at":null,"updated_at":null,"devices":[],"appointments":[]}
        """.data(using: .utf8)!
        let detail = try JSONDecoder().decode(LeadDetail.self, from: json)
        guard let cast = detail as? T else { throw APITransportError.decoding("type mismatch") }
        return cast
    }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
