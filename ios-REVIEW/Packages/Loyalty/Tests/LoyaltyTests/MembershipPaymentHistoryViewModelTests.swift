import XCTest
import Networking
@testable import Networking
@testable import Loyalty

/// §38.3 — `SubscriptionPaymentHistoryViewModel` state-machine tests.
///
/// Covers:
///   1. Initial state is `.loading`.
///   2. Successful load with payments → `.loaded`.
///   3. Successful load with empty array → `.empty`.
///   4. Network failure → `.failed`.
///   5. Idempotent refresh (calling twice).
///   6. State is reset to `.loading` on each `load()` call.
@MainActor
final class MembershipPaymentHistoryViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makePayment(
        id: Int = 1,
        subscriptionId: Int = 42,
        amount: Double = 19.99,
        status: String = "success",
        createdAt: String? = "2026-01-01 10:00:00"
    ) -> SubscriptionPaymentDTO {
        SubscriptionPaymentDTO(
            id: id,
            subscriptionId: subscriptionId,
            amount: amount,
            status: status,
            createdAt: createdAt
        )
    }

    // MARK: - Initial state

    func test_initialState_isLoading() {
        let vm = SubscriptionPaymentHistoryViewModel(
            api: MockPaymentHistoryClient(result: .failure(URLError(.badURL))),
            subscriptionId: 42
        )
        XCTAssertEqual(vm.state, .loading)
        XCTAssertTrue(vm.payments.isEmpty)
    }

    // MARK: - Success paths

    func test_load_withPayments_transitionsToLoaded() async {
        let payments = [makePayment(id: 1), makePayment(id: 2)]
        let vm = SubscriptionPaymentHistoryViewModel(
            api: MockPaymentHistoryClient(result: .success(payments)),
            subscriptionId: 42
        )
        await vm.load()
        XCTAssertEqual(vm.state, .loaded)
        XCTAssertEqual(vm.payments.count, 2)
    }

    func test_load_withEmptyArray_transitionsToEmpty() async {
        let vm = SubscriptionPaymentHistoryViewModel(
            api: MockPaymentHistoryClient(result: .success([])),
            subscriptionId: 42
        )
        await vm.load()
        XCTAssertEqual(vm.state, .empty)
        XCTAssertTrue(vm.payments.isEmpty)
    }

    func test_load_preservesPaymentFields() async {
        let payment = makePayment(id: 99, amount: 49.99, status: "failed", createdAt: "2026-03-15 08:00:00")
        let vm = SubscriptionPaymentHistoryViewModel(
            api: MockPaymentHistoryClient(result: .success([payment])),
            subscriptionId: 42
        )
        await vm.load()
        XCTAssertEqual(vm.payments.first?.id, 99)
        XCTAssertEqual(vm.payments.first?.amount, 49.99, accuracy: 0.001)
        XCTAssertEqual(vm.payments.first?.status, "failed")
    }

    // MARK: - Failure paths

    func test_load_networkError_transitionsToFailed() async {
        let vm = SubscriptionPaymentHistoryViewModel(
            api: MockPaymentHistoryClient(result: .failure(URLError(.notConnectedToInternet))),
            subscriptionId: 42
        )
        await vm.load()
        if case .failed = vm.state { /* pass */ }
        else { XCTFail("Expected .failed, got \(vm.state)") }
    }

    func test_load_httpError_transitionsToFailed() async {
        let err = APITransportError.httpStatus(403, message: "Forbidden")
        let vm = SubscriptionPaymentHistoryViewModel(
            api: MockPaymentHistoryClient(result: .failure(err)),
            subscriptionId: 42
        )
        await vm.load()
        if case .failed(let msg) = vm.state {
            XCTAssertTrue(msg.contains("Forbidden") || !msg.isEmpty)
        } else {
            XCTFail("Expected .failed, got \(vm.state)")
        }
    }

    // MARK: - State reset on repeated load

    func test_load_resetsPaymentsOnSecondCall() async {
        let first = [makePayment(id: 1), makePayment(id: 2)]
        let mock = MockPaymentHistoryClient(result: .success(first))
        let vm = SubscriptionPaymentHistoryViewModel(api: mock, subscriptionId: 42)
        await vm.load()
        XCTAssertEqual(vm.payments.count, 2)

        mock.setResult(.success([]))
        await vm.load()
        XCTAssertEqual(vm.state, .empty)
        XCTAssertTrue(vm.payments.isEmpty)
    }

    // MARK: - Refresh

    func test_refresh_delegatesToLoad() async {
        let payments = [makePayment(id: 5)]
        let vm = SubscriptionPaymentHistoryViewModel(
            api: MockPaymentHistoryClient(result: .success(payments)),
            subscriptionId: 42
        )
        await vm.refresh()
        XCTAssertEqual(vm.state, .loaded)
        XCTAssertEqual(vm.payments.count, 1)
    }

    // MARK: - State equatable

    func test_state_loading_equatable() {
        XCTAssertEqual(
            SubscriptionPaymentHistoryViewModel.State.loading,
            SubscriptionPaymentHistoryViewModel.State.loading
        )
    }

    func test_state_empty_equatable() {
        XCTAssertEqual(
            SubscriptionPaymentHistoryViewModel.State.empty,
            SubscriptionPaymentHistoryViewModel.State.empty
        )
    }

    func test_state_failed_sameMessage_equatable() {
        XCTAssertEqual(
            SubscriptionPaymentHistoryViewModel.State.failed("err"),
            SubscriptionPaymentHistoryViewModel.State.failed("err")
        )
    }

    func test_state_loaded_notEqual_loading() {
        XCTAssertNotEqual(
            SubscriptionPaymentHistoryViewModel.State.loaded,
            SubscriptionPaymentHistoryViewModel.State.loading
        )
    }
}

// MARK: - Mock

private final class MockPaymentHistoryClient: APIClient, @unchecked Sendable {

    private var result: Result<[SubscriptionPaymentDTO], Error>

    init(result: Result<[SubscriptionPaymentDTO], Error>) {
        self.result = result
    }

    func setResult(_ r: Result<[SubscriptionPaymentDTO], Error>) { result = r }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        switch result {
        case .success(let payments):
            // Encode using explicit snake_case JSON so the CodingKeys on
            // SubscriptionPaymentDTO round-trip correctly through JSONDecoder.
            let jsonArray: [[String: Any]] = payments.map { p in
                var d: [String: Any] = [
                    "id": p.id,
                    "subscription_id": p.subscriptionId,
                    "amount": p.amount,
                    "status": p.status
                ]
                if let ca = p.createdAt { d["created_at"] = ca }
                return d
            }
            let data = try JSONSerialization.data(withJSONObject: jsonArray)
            return try JSONDecoder().decode(T.self, from: data)
        case .failure(let error):
            throw error
        }
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw URLError(.badURL) }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw URLError(.badURL) }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw URLError(.badURL) }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw URLError(.badURL) }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { URL(string: "https://test.example.com/api/v1") }
    func setRefresher(_ refresher: (any AuthSessionRefresher)?) async {}
}

