import XCTest
import Networking
@testable import Loyalty

/// §38 — `LoyaltyTiersDisplayViewModel` state-transition tests.
///
/// Uses a `MockTiersAPIClient` that can be configured to return tiers or throw.
@MainActor
final class LoyaltyTiersDisplayViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeTier(id: Int, name: String, price: Double = 9.99, discount: Int = 0) -> MembershipTierDTO {
        MembershipTierDTO(
            id: id,
            name: name,
            slug: name.lowercased(),
            monthlyPrice: price,
            discountPct: discount,
            benefits: [],
            isActive: true
        )
    }

    // MARK: - Initial state

    func test_initialState_isLoading() {
        let vm = LoyaltyTiersDisplayViewModel(api: MockTiersAPIClient(result: .failure(URLError(.badURL))))
        XCTAssertEqual(vm.state, .loading)
        XCTAssertTrue(vm.tiers.isEmpty)
    }

    // MARK: - Load success

    func test_load_withTiers_transitionsToLoaded() async {
        let tiers = [makeTier(id: 1, name: "Bronze"), makeTier(id: 2, name: "Gold")]
        let vm = LoyaltyTiersDisplayViewModel(api: MockTiersAPIClient(result: .success(tiers)))
        await vm.load()
        XCTAssertEqual(vm.state, .loaded)
        XCTAssertEqual(vm.tiers.count, 2)
    }

    func test_load_withTiers_preservesOrder() async {
        let tiers = [
            makeTier(id: 1, name: "Bronze"),
            makeTier(id: 2, name: "Silver"),
            makeTier(id: 3, name: "Gold")
        ]
        let vm = LoyaltyTiersDisplayViewModel(api: MockTiersAPIClient(result: .success(tiers)))
        await vm.load()
        XCTAssertEqual(vm.tiers.map { $0.name }, ["Bronze", "Silver", "Gold"])
    }

    func test_load_emptyTiers_transitionsToComingSoon() async {
        let vm = LoyaltyTiersDisplayViewModel(api: MockTiersAPIClient(result: .success([])))
        await vm.load()
        XCTAssertEqual(vm.state, .comingSoon)
    }

    // MARK: - 402 / 404 / 501 → comingSoon

    func test_load_402_transitionsToComingSoon() async {
        let error = APITransportError.httpStatus(402, message: "Pro required")
        let vm = LoyaltyTiersDisplayViewModel(api: MockTiersAPIClient(result: .failure(error)))
        await vm.load()
        XCTAssertEqual(vm.state, .comingSoon)
    }

    func test_load_404_transitionsToComingSoon() async {
        let error = APITransportError.httpStatus(404, message: nil)
        let vm = LoyaltyTiersDisplayViewModel(api: MockTiersAPIClient(result: .failure(error)))
        await vm.load()
        XCTAssertEqual(vm.state, .comingSoon)
    }

    func test_load_501_transitionsToComingSoon() async {
        let error = APITransportError.httpStatus(501, message: nil)
        let vm = LoyaltyTiersDisplayViewModel(api: MockTiersAPIClient(result: .failure(error)))
        await vm.load()
        XCTAssertEqual(vm.state, .comingSoon)
    }

    // MARK: - Other errors → failed

    func test_load_500_transitionsToFailed() async {
        let error = APITransportError.httpStatus(500, message: "Internal error")
        let vm = LoyaltyTiersDisplayViewModel(api: MockTiersAPIClient(result: .failure(error)))
        await vm.load()
        if case .failed = vm.state {
            // pass
        } else {
            XCTFail("Expected .failed, got \(vm.state)")
        }
    }

    func test_load_networkError_transitionsToFailed() async {
        let error = URLError(.notConnectedToInternet)
        let vm = LoyaltyTiersDisplayViewModel(api: MockTiersAPIClient(result: .failure(error)))
        await vm.load()
        if case .failed = vm.state {
            // pass
        } else {
            XCTFail("Expected .failed, got \(vm.state)")
        }
    }

    // MARK: - Tier discount mapping

    func test_load_tier_discountPct_preserved() async {
        let tiers = [makeTier(id: 1, name: "Gold", price: 19.99, discount: 10)]
        let vm = LoyaltyTiersDisplayViewModel(api: MockTiersAPIClient(result: .success(tiers)))
        await vm.load()
        XCTAssertEqual(vm.tiers.first?.discountPct, 10)
        XCTAssertEqual(vm.tiers.first?.monthlyPrice ?? 0.0, 19.99, accuracy: 0.01)
    }

    // MARK: - State equatability

    func test_state_loading_equalToLoading() {
        XCTAssertEqual(LoyaltyTiersDisplayViewModel.State.loading, .loading)
    }

    func test_state_loaded_equalToLoaded() {
        XCTAssertEqual(LoyaltyTiersDisplayViewModel.State.loaded, .loaded)
    }

    func test_state_comingSoon_equalToComingSoon() {
        XCTAssertEqual(LoyaltyTiersDisplayViewModel.State.comingSoon, .comingSoon)
    }

    func test_state_failed_sameMessage_equal() {
        XCTAssertEqual(
            LoyaltyTiersDisplayViewModel.State.failed("err"),
            .failed("err")
        )
    }

    func test_state_failed_differentMessage_notEqual() {
        XCTAssertNotEqual(
            LoyaltyTiersDisplayViewModel.State.failed("a"),
            .failed("b")
        )
    }

    func test_state_loading_notEqualComingSoon() {
        XCTAssertNotEqual(
            LoyaltyTiersDisplayViewModel.State.loading,
            .comingSoon
        )
    }
}

// MARK: - MockTiersAPIClient

private final class MockTiersAPIClient: APIClient, @unchecked Sendable {

    private let tiersResult: Result<[MembershipTierDTO], Error>

    init(result: Result<[MembershipTierDTO], Error>) {
        self.tiersResult = result
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        // Only handle the tiers endpoint
        if path.hasSuffix("/tiers") || path.contains("membership/tiers") {
            switch tiersResult {
            case .success(let tiers):
                // Type-erase safely
                if let result = tiers as? T {
                    return result
                }
                throw URLError(.cannotParseResponse)
            case .failure(let error):
                throw error
            }
        }
        throw URLError(.badURL)
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw URLError(.badURL) }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw URLError(.badURL) }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw URLError(.badURL) }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw URLError(.badURL) }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: (any AuthSessionRefresher)?) async {}
}
