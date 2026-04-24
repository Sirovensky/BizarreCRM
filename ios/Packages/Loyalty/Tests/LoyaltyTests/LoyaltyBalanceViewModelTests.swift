import XCTest
import Networking
@testable import Loyalty

/// §38 — `LoyaltyBalanceViewModel` state-transition tests.
///
/// `getLoyaltyBalance` now assembles data from:
///   - `GET /customers/:id/analytics` (lifetime spend)
///   - `GET /membership/customer/:id` (tier name from subscription)
///
/// Tests use `MockLoyaltyBalanceAPIClient` to inject controlled responses
/// without needing a real server.
///   1. The view-model's initial state.
///   2. Network path → `.loaded` with correct balance.
///   3. 404 path → `.comingSoon`.
///   4. Other error → `.failed`.
///   5. The `LoyaltyBalanceViewModel.State` equatable conformance.
@MainActor
final class LoyaltyBalanceViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeBalance(
        customerId: Int64 = 1,
        points: Int = 500,
        tier: String = "gold",
        lifetimeSpendCents: Int = 10_000,
        memberSince: String = "2023-01-01"
    ) -> LoyaltyBalance {
        LoyaltyBalance(
            customerId: customerId,
            points: points,
            tier: tier,
            lifetimeSpendCents: lifetimeSpendCents,
            memberSince: memberSince
        )
    }

    // MARK: - State equatable

    func test_state_equatable_loading() {
        XCTAssertEqual(
            LoyaltyBalanceViewModel.State.loading,
            LoyaltyBalanceViewModel.State.loading
        )
    }

    func test_state_equatable_loaded() {
        XCTAssertEqual(
            LoyaltyBalanceViewModel.State.loaded,
            LoyaltyBalanceViewModel.State.loaded
        )
    }

    func test_state_equatable_comingSoon() {
        XCTAssertEqual(
            LoyaltyBalanceViewModel.State.comingSoon,
            LoyaltyBalanceViewModel.State.comingSoon
        )
    }

    func test_state_equatable_failed_sameMessage() {
        XCTAssertEqual(
            LoyaltyBalanceViewModel.State.failed("oops"),
            LoyaltyBalanceViewModel.State.failed("oops")
        )
    }

    func test_state_equatable_failed_differentMessage_notEqual() {
        XCTAssertNotEqual(
            LoyaltyBalanceViewModel.State.failed("a"),
            LoyaltyBalanceViewModel.State.failed("b")
        )
    }

    func test_state_loading_notEqual_loaded() {
        XCTAssertNotEqual(
            LoyaltyBalanceViewModel.State.loading,
            LoyaltyBalanceViewModel.State.loaded
        )
    }

    // MARK: - Initial state

    func test_initialState_isLoading() {
        let vm = LoyaltyBalanceViewModel(api: MockLoyaltyBalanceAPIClient(result: .failure(URLError(.badURL))))
        XCTAssertEqual(vm.state, .loading)
        XCTAssertNil(vm.balance)
        XCTAssertNil(vm.passData)
    }

    // MARK: - loadBalance — 404 → comingSoon

    func test_loadBalance_404_transitionsToComingSoon() async {
        let error = APITransportError.httpStatus(404, message: nil)
        let vm = LoyaltyBalanceViewModel(api: MockLoyaltyBalanceAPIClient(result: .failure(error)))
        await vm.loadBalance(customerId: 1)
        XCTAssertEqual(vm.state, .comingSoon)
        XCTAssertNil(vm.balance)
    }

    func test_loadBalance_501_transitionsToComingSoon() async {
        let error = APITransportError.httpStatus(501, message: nil)
        let vm = LoyaltyBalanceViewModel(api: MockLoyaltyBalanceAPIClient(result: .failure(error)))
        await vm.loadBalance(customerId: 1)
        XCTAssertEqual(vm.state, .comingSoon)
    }

    // MARK: - loadBalance — network failure → failed

    func test_loadBalance_networkError_transitionsToFailed() async {
        let error = URLError(.notConnectedToInternet)
        let vm = LoyaltyBalanceViewModel(api: MockLoyaltyBalanceAPIClient(result: .failure(error)))
        await vm.loadBalance(customerId: 1)
        if case .failed = vm.state {
            // pass
        } else {
            XCTFail("Expected .failed, got \(vm.state)")
        }
    }

    // MARK: - loadBalance — success → loaded

    func test_loadBalance_success_transitionsToLoaded() async {
        let balance = makeBalance(points: 200, tier: "gold")
        let vm = LoyaltyBalanceViewModel(api: MockLoyaltyBalanceAPIClient(result: .success(balance)))
        await vm.loadBalance(customerId: 1)
        XCTAssertEqual(vm.state, .loaded)
        XCTAssertEqual(vm.balance?.tier, "gold")
        XCTAssertEqual(vm.balance?.points, 200)
    }

    func test_loadBalance_success_passDataRemainNil() async {
        let balance = makeBalance()
        let vm = LoyaltyBalanceViewModel(api: MockLoyaltyBalanceAPIClient(result: .success(balance)))
        await vm.loadBalance(customerId: 1)
        XCTAssertNil(vm.passData)
    }

    // MARK: - downloadPass — 501 → comingSoon

    func test_downloadPass_501_transitionsToComingSoon() async {
        let error = APITransportError.httpStatus(501, message: "pkpass not configured")
        let vm = LoyaltyBalanceViewModel(api: MockLoyaltyBalanceAPIClient(passError: error))
        await vm.downloadPass(customerId: 1)
        XCTAssertEqual(vm.state, .comingSoon)
        XCTAssertNil(vm.passData)
    }

    // MARK: - Multiple calls

    func test_loadBalance_calledTwice_stateIsLoaded() async {
        let balance = makeBalance(points: 100, tier: "silver")
        let vm = LoyaltyBalanceViewModel(api: MockLoyaltyBalanceAPIClient(result: .success(balance)))
        await vm.loadBalance(customerId: 1)
        await vm.loadBalance(customerId: 2)
        XCTAssertEqual(vm.state, .loaded)
    }

    // MARK: - LoyaltyBalance DTO equality via init

    func test_loyaltyBalance_init_fieldsPreserved() {
        let balance = makeBalance(points: 999, tier: "platinum")
        XCTAssertEqual(balance.points, 999)
        XCTAssertEqual(balance.tier, "platinum")
        XCTAssertEqual(balance.lifetimeSpendCents, 10_000)
    }

    func test_loyaltyBalance_customerId_preserved() {
        let balance = makeBalance(customerId: 77)
        XCTAssertEqual(balance.customerId, 77)
    }
}

// MARK: - MockLoyaltyBalanceAPIClient

/// Mock that controls `getLoyaltyBalance` + `fetchLoyaltyPass` responses.
/// Conforms to `APIClient` but routes only the loyalty-relevant calls.
private final class MockLoyaltyBalanceAPIClient: APIClient, @unchecked Sendable {

    private let balanceResult: Result<LoyaltyBalance, Error>
    private let passError: Error?

    init(result: Result<LoyaltyBalance, Error>, passError: Error? = nil) {
        self.balanceResult = result
        self.passError = passError
    }

    /// Convenience init for pass-only error testing.
    init(passError: Error) {
        self.balanceResult = .failure(URLError(.badURL))
        self.passError = passError
    }

    // Intercept `getLoyaltyBalance` calls (which internally call `get`).
    // The first `get` call is for analytics, so we return a fake analytics
    // payload that maps to the configured balance, OR throw the configured error.
    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        // On any analytics call, forward the result.
        switch balanceResult {
        case .success(let balance):
            // For analytics path, return a fake analytics DTO.
            if path.contains("/analytics") {
                struct FakeAnalytics: Encodable {
                    let total_tickets: Int
                    let lifetime_value: Double
                    let first_visit: String?
                }
                let a = FakeAnalytics(
                    total_tickets: 1,
                    lifetime_value: Double(balance.lifetimeSpendCents) / 100.0,
                    first_visit: balance.memberSince
                )
                let data = try JSONEncoder().encode(a)
                return try JSONDecoder().decode(T.self, from: data)
            }
            // For membership path, return nil (no active subscription).
            if path.contains("/membership/customer") {
                // Decode null as Optional<CustomerSubscriptionDTO>
                let nullData = "null".data(using: .utf8)!
                return try JSONDecoder().decode(T.self, from: nullData)
            }
            throw URLError(.badURL)
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
    func currentBaseURL() async -> URL? {
        // Return a fake base URL so the pass fetch won't throw noBaseURL first.
        URL(string: "https://test.example.com/api/v1")
    }
    func setRefresher(_ refresher: (any AuthSessionRefresher)?) async {}
}
