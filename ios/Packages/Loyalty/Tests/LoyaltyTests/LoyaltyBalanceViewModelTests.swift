import XCTest
import Networking
@testable import Loyalty

/// §38 — `LoyaltyBalanceViewModel` state-transition tests.
///
/// Because `getLoyaltyBalance` and `fetchLoyaltyPass` are extension methods
/// on the `APIClient` protocol (defined in `LoyaltyEndpoints.swift`), they
/// always throw `APITransportError.httpStatus(501, ...)` in the current stub
/// implementation. This is intentional — the server endpoint does not yet
/// exist. The test suite validates:
///   1. The view-model's initial state.
///   2. The 501 stub path → `.comingSoon` transition for both balance + pass.
///   3. The `LoyaltyBalanceViewModel.State` equatable conformance.
///   4. Helper/filter logic that is pure (no network call needed).
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
        let vm = LoyaltyBalanceViewModel(api: APIClientImpl())
        XCTAssertEqual(vm.state, .loading)
        XCTAssertNil(vm.balance)
        XCTAssertNil(vm.passData)
    }

    // MARK: - loadBalance — stub returns 501 → comingSoon

    func test_loadBalance_stub501_transitionsToComingSoon() async {
        // The endpoint is stubbed server-side → always throws 501.
        // vm should land in .comingSoon.
        let vm = LoyaltyBalanceViewModel(api: APIClientImpl())
        await vm.loadBalance(customerId: 1)
        XCTAssertEqual(vm.state, .comingSoon)
        XCTAssertNil(vm.balance)
    }

    func test_loadBalance_comingSoon_passDataStillNil() async {
        let vm = LoyaltyBalanceViewModel(api: APIClientImpl())
        await vm.loadBalance(customerId: 1)
        // passData must be nil — no pass was downloaded
        XCTAssertNil(vm.passData)
    }

    // MARK: - downloadPass — stub returns 501 → comingSoon

    func test_downloadPass_stub501_transitionsToComingSoon() async {
        let vm = LoyaltyBalanceViewModel(api: APIClientImpl())
        await vm.downloadPass(customerId: 1)
        XCTAssertEqual(vm.state, .comingSoon)
        XCTAssertNil(vm.passData)
    }

    // MARK: - Multiple calls

    func test_loadBalance_calledTwice_stateIsComingSoon() async {
        let vm = LoyaltyBalanceViewModel(api: APIClientImpl())
        await vm.loadBalance(customerId: 1)
        await vm.loadBalance(customerId: 2)
        XCTAssertEqual(vm.state, .comingSoon)
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
