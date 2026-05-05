import XCTest
import Networking
@testable import Networking
@testable import Loyalty

/// §38.4 — `MembershipRedeemViewModel` state-machine and validation tests.
///
/// Covers:
///   1. Initial state is `.idle`.
///   2. `isValid` rules (zero points, over balance, valid amount).
///   3. `validationMessage` covers all invalid states.
///   4. Successful redemption → `.redeemed`.
///   5. 501 response → `.notYetAvailable` (server not yet wired).
///   6. 404 response → `.notYetAvailable`.
///   7. Other HTTP error → `.failed`.
///   8. `redeem()` is a no-op when `isValid` is false.
@MainActor
final class MembershipRedeemViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeVM(
        availablePoints: Int = 500,
        redeemResult: Result<MembershipRedeemResultDTO, Error> = .success(
            MembershipRedeemResultDTO(redeemed: true, remainingPoints: 300, creditCents: nil)
        )
    ) -> MembershipRedeemViewModel {
        MembershipRedeemViewModel(
            api: MockRedeemClient(result: redeemResult),
            subscriptionId: 42,
            availablePoints: availablePoints
        )
    }

    // MARK: - Initial state

    func test_initialState_isIdle() {
        let vm = makeVM()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertEqual(vm.pointsToRedeem, 0)
    }

    func test_initialState_availablePoints_preserved() {
        let vm = makeVM(availablePoints: 250)
        XCTAssertEqual(vm.availablePoints, 250)
    }

    // MARK: - Validation: isValid

    func test_isValid_zeroPoints_isFalse() {
        let vm = makeVM()
        vm.pointsToRedeem = 0
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_negativePoints_isFalse() {
        let vm = makeVM()
        vm.pointsToRedeem = -10
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_exceedsAvailable_isFalse() {
        let vm = makeVM(availablePoints: 100)
        vm.pointsToRedeem = 101
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_exactlyAvailable_isTrue() {
        let vm = makeVM(availablePoints: 100)
        vm.pointsToRedeem = 100
        XCTAssertTrue(vm.isValid)
    }

    func test_isValid_withinLimit_isTrue() {
        let vm = makeVM(availablePoints: 500)
        vm.pointsToRedeem = 200
        XCTAssertTrue(vm.isValid)
    }

    // MARK: - Validation: validationMessage

    func test_validationMessage_zeroPoints_isNotNil() {
        let vm = makeVM()
        vm.pointsToRedeem = 0
        XCTAssertNotNil(vm.validationMessage)
    }

    func test_validationMessage_exceedsBalance_mentionsAvailable() {
        let vm = makeVM(availablePoints: 50)
        vm.pointsToRedeem = 999
        let msg = vm.validationMessage ?? ""
        XCTAssertTrue(msg.contains("50"))
    }

    func test_validationMessage_validAmount_isNil() {
        let vm = makeVM(availablePoints: 500)
        vm.pointsToRedeem = 100
        XCTAssertNil(vm.validationMessage)
    }

    // MARK: - Successful redemption

    func test_redeem_success_transitionsToRedeemed() async {
        let result = MembershipRedeemResultDTO(redeemed: true, remainingPoints: 400, creditCents: nil)
        let vm = MembershipRedeemViewModel(
            api: MockRedeemClient(result: .success(result)),
            subscriptionId: 42,
            availablePoints: 500
        )
        vm.pointsToRedeem = 100
        await vm.redeem()
        if case .redeemed(let pts, let remaining) = vm.state {
            XCTAssertEqual(pts, 100)
            XCTAssertEqual(remaining, 400)
        } else {
            XCTFail("Expected .redeemed, got \(vm.state)")
        }
    }

    func test_redeem_success_nilRemaining_redeemed() async {
        let result = MembershipRedeemResultDTO(redeemed: true, remainingPoints: nil, creditCents: nil)
        let vm = MembershipRedeemViewModel(
            api: MockRedeemClient(result: .success(result)),
            subscriptionId: 42,
            availablePoints: 500
        )
        vm.pointsToRedeem = 50
        await vm.redeem()
        if case .redeemed(let pts, let remaining) = vm.state {
            XCTAssertEqual(pts, 50)
            XCTAssertNil(remaining)
        } else {
            XCTFail("Expected .redeemed, got \(vm.state)")
        }
    }

    // MARK: - 501 / 404 → notYetAvailable

    func test_redeem_501_transitionsToNotYetAvailable() async {
        let err = APITransportError.httpStatus(501, message: "Not implemented")
        let vm = MembershipRedeemViewModel(
            api: MockRedeemClient(result: .failure(err)),
            subscriptionId: 42,
            availablePoints: 500
        )
        vm.pointsToRedeem = 100
        await vm.redeem()
        XCTAssertEqual(vm.state, .notYetAvailable)
    }

    func test_redeem_404_transitionsToNotYetAvailable() async {
        let err = APITransportError.httpStatus(404, message: "Not found")
        let vm = MembershipRedeemViewModel(
            api: MockRedeemClient(result: .failure(err)),
            subscriptionId: 42,
            availablePoints: 500
        )
        vm.pointsToRedeem = 100
        await vm.redeem()
        XCTAssertEqual(vm.state, .notYetAvailable)
    }

    // MARK: - Other HTTP error → failed

    func test_redeem_403_transitionsToFailed() async {
        let err = APITransportError.httpStatus(403, message: "Forbidden")
        let vm = MembershipRedeemViewModel(
            api: MockRedeemClient(result: .failure(err)),
            subscriptionId: 42,
            availablePoints: 500
        )
        vm.pointsToRedeem = 100
        await vm.redeem()
        if case .failed = vm.state { /* pass */ }
        else { XCTFail("Expected .failed, got \(vm.state)") }
    }

    func test_redeem_networkError_transitionsToFailed() async {
        let vm = MembershipRedeemViewModel(
            api: MockRedeemClient(result: .failure(URLError(.notConnectedToInternet))),
            subscriptionId: 42,
            availablePoints: 500
        )
        vm.pointsToRedeem = 100
        await vm.redeem()
        if case .failed = vm.state { /* pass */ }
        else { XCTFail("Expected .failed, got \(vm.state)") }
    }

    // MARK: - No-op when invalid

    func test_redeem_invalidPoints_doesNotChangeState() async {
        let vm = makeVM()
        vm.pointsToRedeem = 0
        await vm.redeem()
        XCTAssertEqual(vm.state, .idle)
    }

    // MARK: - State equatable

    func test_state_idle_equatable() {
        XCTAssertEqual(MembershipRedeemViewModel.State.idle, .idle)
    }

    func test_state_notYetAvailable_equatable() {
        XCTAssertEqual(MembershipRedeemViewModel.State.notYetAvailable, .notYetAvailable)
    }

    func test_state_failed_sameMessage_equatable() {
        XCTAssertEqual(
            MembershipRedeemViewModel.State.failed("err"),
            MembershipRedeemViewModel.State.failed("err")
        )
    }

    func test_state_redeemed_sameValues_equatable() {
        XCTAssertEqual(
            MembershipRedeemViewModel.State.redeemed(100, remainingPoints: 400),
            MembershipRedeemViewModel.State.redeemed(100, remainingPoints: 400)
        )
    }

    func test_state_redeemed_differentValues_notEqual() {
        XCTAssertNotEqual(
            MembershipRedeemViewModel.State.redeemed(100, remainingPoints: 400),
            MembershipRedeemViewModel.State.redeemed(200, remainingPoints: 300)
        )
    }
}

// MARK: - Mock

private final class MockRedeemClient: APIClient, @unchecked Sendable {

    private let result: Result<MembershipRedeemResultDTO, Error>

    init(result: Result<MembershipRedeemResultDTO, Error>) {
        self.result = result
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        switch result {
        case .success(let dto):
            // Encode with explicit snake_case keys
            let json: [String: Any?] = [
                "redeemed": dto.redeemed,
                "remaining_points": dto.remainingPoints,
                "credit_cents": dto.creditCents
            ]
            let cleaned = json.compactMapValues { $0 }
            let data = try JSONSerialization.data(withJSONObject: cleaned)
            return try JSONDecoder().decode(T.self, from: data)
        case .failure(let error):
            throw error
        }
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T { throw URLError(.badURL) }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw URLError(.badURL) }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw URLError(.badURL) }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw URLError(.badURL) }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { URL(string: "https://test.example.com/api/v1") }
    func setRefresher(_ refresher: (any AuthSessionRefresher)?) async {}
}
