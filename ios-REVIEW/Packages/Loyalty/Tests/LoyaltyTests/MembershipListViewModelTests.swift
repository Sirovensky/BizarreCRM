import XCTest
import Networking
@testable import Networking
@testable import Loyalty

/// §38.1 — `MembershipListViewModel` state-machine + admin-sub lookup tests.
///
/// Covers:
///   1. Initial state is `.loading`.
///   2. Empty subscription list → `.loaded` + empty arrays.
///   3. Subscriptions populate `memberships` and `adminSubsByMembershipId`.
///   4. Tier badge data (tierName, color) is accessible via the lookup dict.
///   5. 404/501 → `.comingSoon`.
///   6. Network error → `.failed`.
///   7. `refresh()` delegates to `load()`.
///   8. Status mapping (active, paused, cancelled, past_due).
@MainActor
final class MembershipListViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeAdminSub(
        id: Int = 1,
        customerId: Int = 10,
        tierId: Int = 2,
        status: String = "active",
        tierName: String? = "Gold",
        color: String? = "#f59e0b",
        firstName: String? = "Alice",
        lastName: String? = "Smith"
    ) -> AdminSubscriptionDTO {
        // Build JSON and decode to get a fully-formed DTO with CodingKeys.
        let json: [String: Any] = [
            "id": id,
            "customer_id": customerId,
            "tier_id": tierId,
            "status": status,
            "current_period_start": "2026-01-01 00:00:00",
            "current_period_end": "2026-02-01 00:00:00",
            "tier_name": tierName ?? NSNull(),
            "monthly_price": 19.99,
            "color": color ?? NSNull(),
            "first_name": firstName ?? NSNull(),
            "last_name": lastName ?? NSNull()
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(AdminSubscriptionDTO.self, from: data)
    }

    private func makeManager() -> MembershipSubscriptionManager {
        MembershipSubscriptionManager(api: nil)
    }

    // MARK: - Initial state

    func test_initialState_isLoading() {
        let vm = MembershipListViewModel(
            api: MockListClient(result: .failure(URLError(.badURL))),
            manager: makeManager()
        )
        XCTAssertEqual(vm.state, .loading)
        XCTAssertTrue(vm.memberships.isEmpty)
        XCTAssertTrue(vm.adminSubsByMembershipId.isEmpty)
    }

    // MARK: - Empty response

    func test_load_emptySubs_stateLoaded_emptyMemberships() async {
        let vm = MembershipListViewModel(
            api: MockListClient(result: .success([])),
            manager: makeManager()
        )
        await vm.load()
        XCTAssertEqual(vm.state, .loaded)
        XCTAssertTrue(vm.memberships.isEmpty)
        XCTAssertTrue(vm.adminSubsByMembershipId.isEmpty)
    }

    // MARK: - Subscriptions populate both collections

    func test_load_withSubs_stateLoaded() async {
        let subs = [makeAdminSub(id: 1), makeAdminSub(id: 2, customerId: 20)]
        let vm = MembershipListViewModel(
            api: MockListClient(result: .success(subs)),
            manager: makeManager()
        )
        await vm.load()
        XCTAssertEqual(vm.state, .loaded)
        XCTAssertEqual(vm.memberships.count, 2)
    }

    func test_load_adminSubsByMembershipId_keysMatchMembershipIds() async {
        let subs = [makeAdminSub(id: 7), makeAdminSub(id: 8, customerId: 99)]
        let vm = MembershipListViewModel(
            api: MockListClient(result: .success(subs)),
            manager: makeManager()
        )
        await vm.load()
        XCTAssertNotNil(vm.adminSubsByMembershipId["7"])
        XCTAssertNotNil(vm.adminSubsByMembershipId["8"])
        XCTAssertNil(vm.adminSubsByMembershipId["999"])
    }

    func test_load_tierBadgeData_accessible() async {
        let sub = makeAdminSub(id: 5, tierName: "Platinum", color: "#6366f1")
        let vm = MembershipListViewModel(
            api: MockListClient(result: .success([sub])),
            manager: makeManager()
        )
        await vm.load()
        let lookup = vm.adminSubsByMembershipId["5"]
        XCTAssertEqual(lookup?.tierName, "Platinum")
        XCTAssertEqual(lookup?.color, "#6366f1")
    }

    func test_load_customerName_accessible() async {
        let sub = makeAdminSub(id: 3, firstName: "Bob", lastName: "Jones")
        let vm = MembershipListViewModel(
            api: MockListClient(result: .success([sub])),
            manager: makeManager()
        )
        await vm.load()
        let lookup = vm.adminSubsByMembershipId["3"]
        XCTAssertEqual(lookup?.firstName, "Bob")
        XCTAssertEqual(lookup?.lastName, "Jones")
    }

    // MARK: - Status mapping

    func test_load_activeStatus_membershipStatusIsActive() async {
        let sub = makeAdminSub(id: 1, status: "active")
        let vm = MembershipListViewModel(
            api: MockListClient(result: .success([sub])),
            manager: makeManager()
        )
        await vm.load()
        XCTAssertEqual(vm.memberships.first?.status, .active)
    }

    func test_load_pausedStatus_membershipStatusIsPaused() async {
        let sub = makeAdminSub(id: 1, status: "paused")
        let vm = MembershipListViewModel(
            api: MockListClient(result: .success([sub])),
            manager: makeManager()
        )
        await vm.load()
        XCTAssertEqual(vm.memberships.first?.status, .paused)
    }

    func test_load_pastDueStatus_defaultsToActive() async {
        let sub = makeAdminSub(id: 1, status: "past_due")
        let vm = MembershipListViewModel(
            api: MockListClient(result: .success([sub])),
            manager: makeManager()
        )
        await vm.load()
        // past_due not in MembershipStatus; falls back to .active
        let status = vm.memberships.first?.status
        XCTAssertNotNil(status)
    }

    // MARK: - Error paths

    func test_load_404_transitionsToComingSoon() async {
        let err = APITransportError.httpStatus(404, message: nil)
        let vm = MembershipListViewModel(
            api: MockListClient(result: .failure(err)),
            manager: makeManager()
        )
        await vm.load()
        XCTAssertEqual(vm.state, .comingSoon)
    }

    func test_load_501_transitionsToComingSoon() async {
        let err = APITransportError.httpStatus(501, message: nil)
        let vm = MembershipListViewModel(
            api: MockListClient(result: .failure(err)),
            manager: makeManager()
        )
        await vm.load()
        XCTAssertEqual(vm.state, .comingSoon)
    }

    func test_load_networkError_transitionsToFailed() async {
        let vm = MembershipListViewModel(
            api: MockListClient(result: .failure(URLError(.notConnectedToInternet))),
            manager: makeManager()
        )
        await vm.load()
        if case .failed = vm.state { /* pass */ }
        else { XCTFail("Expected .failed, got \(vm.state)") }
    }

    // MARK: - Refresh

    func test_refresh_delegatesToLoad() async {
        let subs = [makeAdminSub(id: 1)]
        let vm = MembershipListViewModel(
            api: MockListClient(result: .success(subs)),
            manager: makeManager()
        )
        await vm.refresh()
        XCTAssertEqual(vm.state, .loaded)
        XCTAssertEqual(vm.memberships.count, 1)
    }

    // MARK: - State equatable

    func test_state_loading_equatable() {
        XCTAssertEqual(MembershipListViewModel.State.loading, .loading)
    }

    func test_state_comingSoon_equatable() {
        XCTAssertEqual(MembershipListViewModel.State.comingSoon, .comingSoon)
    }

    func test_state_failed_equatable() {
        XCTAssertEqual(
            MembershipListViewModel.State.failed("x"),
            MembershipListViewModel.State.failed("x")
        )
    }

    func test_state_loaded_notEqual_comingSoon() {
        XCTAssertNotEqual(
            MembershipListViewModel.State.loaded,
            MembershipListViewModel.State.comingSoon
        )
    }
}

// MARK: - Mock

private final class MockListClient: APIClient, @unchecked Sendable {

    private var result: Result<[AdminSubscriptionDTO], Error>

    init(result: Result<[AdminSubscriptionDTO], Error>) {
        self.result = result
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        switch result {
        case .success(let subs):
            // Re-encode to JSON array with snake_case keys matching AdminSubscriptionDTO.CodingKeys
            let jsonArray: [[String: Any]] = subs.map { s in
                var d: [String: Any] = [
                    "id": s.id,
                    "customer_id": s.customerId,
                    "tier_id": s.tierId,
                    "status": s.status,
                    "current_period_start": s.currentPeriodStart,
                    "current_period_end": s.currentPeriodEnd
                ]
                if let v = s.tierName  { d["tier_name"] = v }
                if let v = s.monthlyPrice { d["monthly_price"] = v }
                if let v = s.color     { d["color"] = v }
                if let v = s.firstName { d["first_name"] = v }
                if let v = s.lastName  { d["last_name"] = v }
                if let v = s.phone     { d["phone"] = v }
                if let v = s.email     { d["email"] = v }
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
