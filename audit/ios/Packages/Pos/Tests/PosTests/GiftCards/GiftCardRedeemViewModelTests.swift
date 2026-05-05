#if canImport(UIKit)
import XCTest
@testable import Pos
@testable import Networking

/// Tests for ``GiftCardRedeemViewModel``.
///
/// Stubbed via `MockRedeemAPIClient` — no network required.
@MainActor
final class GiftCardRedeemViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeActiveCard(balanceCents: Int = 10_000) -> GiftCard {
        GiftCard(id: 1, code: "ACTIVE01", balanceCents: balanceCents, currency: "USD", expiresAt: nil, active: true)
    }

    private func makeInactiveCard() -> GiftCard {
        GiftCard(id: 2, code: "INACTIVE", balanceCents: 5_000, currency: "USD", expiresAt: nil, active: false)
    }

    private func makeAPI(
        redeemResult: Result<RedeemGiftCardResponse, Error>? = nil
    ) -> MockRedeemAPIClient {
        MockRedeemAPIClient(redeemResult: redeemResult)
    }

    // MARK: - Initial state

    func test_initial_state_isIdle() {
        let vm = GiftCardRedeemViewModel(api: makeAPI())
        XCTAssertEqual(vm.state, .idle)
    }

    func test_initial_card_isNil() {
        let vm = GiftCardRedeemViewModel(api: makeAPI())
        XCTAssertNil(vm.card)
    }

    // MARK: - Validation

    func test_validationError_noCard() {
        let vm = GiftCardRedeemViewModel(api: makeAPI())
        XCTAssertNotNil(vm.validationError)
    }

    func test_validationError_inactiveCard() {
        let vm = GiftCardRedeemViewModel(api: makeAPI())
        vm.card = makeInactiveCard()
        vm.amountInput = "1000"
        XCTAssertNotNil(vm.validationError)
        XCTAssertTrue(vm.validationError!.lowercased().contains("active"))
    }

    func test_validationError_zeroAmount() {
        let vm = GiftCardRedeemViewModel(api: makeAPI())
        vm.card = makeActiveCard()
        vm.amountInput = "0"
        XCTAssertNotNil(vm.validationError)
    }

    func test_validationError_exceedsBalance() {
        let vm = GiftCardRedeemViewModel(api: makeAPI())
        vm.card = makeActiveCard(balanceCents: 5_000)
        vm.amountInput = "6000"
        XCTAssertNotNil(vm.validationError)
        XCTAssertTrue(vm.validationError!.lowercased().contains("balance"))
    }

    func test_validationError_exactlyBalance_isValid() {
        let vm = GiftCardRedeemViewModel(api: makeAPI())
        vm.card = makeActiveCard(balanceCents: 5_000)
        vm.amountInput = "5000"
        XCTAssertNil(vm.validationError)
    }

    func test_validationError_nil_whenValid() {
        let vm = GiftCardRedeemViewModel(api: makeAPI())
        vm.card = makeActiveCard()
        vm.amountInput = "1000"
        XCTAssertNil(vm.validationError)
    }

    // MARK: - canRedeem

    func test_canRedeem_false_whenNoCard() {
        let vm = GiftCardRedeemViewModel(api: makeAPI())
        XCTAssertFalse(vm.canRedeem)
    }

    func test_canRedeem_true_whenValid() {
        let vm = GiftCardRedeemViewModel(api: makeAPI())
        vm.card = makeActiveCard()
        vm.amountInput = "500"
        XCTAssertTrue(vm.canRedeem)
    }

    // MARK: - previewRemainingCents

    func test_previewRemaining_nilWhenInvalid() {
        let vm = GiftCardRedeemViewModel(api: makeAPI())
        vm.card = makeActiveCard(balanceCents: 5_000)
        vm.amountInput = "9999"
        XCTAssertNil(vm.previewRemainingCents)
    }

    func test_previewRemaining_correctWhenValid() {
        let vm = GiftCardRedeemViewModel(api: makeAPI())
        vm.card = makeActiveCard(balanceCents: 5_000)
        vm.amountInput = "2000"
        XCTAssertEqual(vm.previewRemainingCents, 3_000)
    }

    func test_previewRemaining_zeroWhenFullRedeem() {
        let vm = GiftCardRedeemViewModel(api: makeAPI())
        vm.card = makeActiveCard(balanceCents: 5_000)
        vm.amountInput = "5000"
        XCTAssertEqual(vm.previewRemainingCents, 0)
    }

    // MARK: - redeem()

    func test_redeem_success_setsRedeemedState() async {
        let response = RedeemGiftCardResponse(remainingBalanceCents: 8_000, transactionId: nil)
        let api = makeAPI(redeemResult: .success(response))
        let vm = GiftCardRedeemViewModel(api: api)
        vm.card = makeActiveCard(balanceCents: 10_000)
        vm.amountInput = "2000"
        await vm.redeem()
        if case .redeemed(let remaining) = vm.state {
            XCTAssertEqual(remaining, 8_000)
        } else {
            XCTFail("Expected .redeemed, got \(vm.state)")
        }
    }

    func test_redeem_failure_setsFailureState() async {
        let api = makeAPI(redeemResult: .failure(MockAPIError()))
        let vm = GiftCardRedeemViewModel(api: api)
        vm.card = makeActiveCard()
        vm.amountInput = "1000"
        await vm.redeem()
        if case .failure = vm.state { /* pass */ }
        else { XCTFail("Expected .failure, got \(vm.state)") }
    }

    func test_redeem_invalidAmount_doesNotCallAPI() async {
        let api = makeAPI(redeemResult: .success(RedeemGiftCardResponse(remainingBalanceCents: 0, transactionId: nil)))
        let vm = GiftCardRedeemViewModel(api: api)
        vm.card = makeActiveCard()
        vm.amountInput = "0"
        await vm.redeem()
        XCTAssertFalse(api.redeemCalled)
        XCTAssertEqual(vm.state, .idle)
    }

    func test_redeem_noCard_doesNotCallAPI() async {
        let api = makeAPI(redeemResult: .success(RedeemGiftCardResponse(remainingBalanceCents: 0, transactionId: nil)))
        let vm = GiftCardRedeemViewModel(api: api)
        vm.amountInput = "500"
        await vm.redeem()
        XCTAssertFalse(api.redeemCalled)
    }

    // MARK: - reset()

    func test_reset_clearsFieldsAndState() async {
        let response = RedeemGiftCardResponse(remainingBalanceCents: 0, transactionId: 7)
        let api = makeAPI(redeemResult: .success(response))
        let vm = GiftCardRedeemViewModel(api: api)
        vm.card = makeActiveCard()
        vm.amountInput = "1000"
        vm.reason = "Test"
        await vm.redeem()
        vm.reset()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertEqual(vm.amountInput, "")
        XCTAssertEqual(vm.reason, "")
    }
}

// MARK: - MockRedeemAPIClient

/// Minimal mock for `GiftCardRedeemViewModelTests`.
/// Stubs `redeemGiftCard`; all other calls throw `URLError(.badURL)`.
final class MockRedeemAPIClient: APIClient, @unchecked Sendable {
    var redeemResult: Result<RedeemGiftCardResponse, Error>?
    private(set) var redeemCalled = false

    init(redeemResult: Result<RedeemGiftCardResponse, Error>? = nil) {
        self.redeemResult = redeemResult
    }

    func get<T: Decodable & Sendable>(
        _ path: String, query: [URLQueryItem]?, as type: T.Type
    ) async throws -> T { throw URLError(.badURL) }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T {
        if path.contains("/redeem") {
            redeemCalled = true
            guard let result = redeemResult else { throw MockAPIError() }
            return try result.get() as! T
        }
        throw URLError(.badURL)
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T { throw URLError(.badURL) }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T { throw URLError(.badURL) }

    func delete(_ path: String) async throws {}

    func getEnvelope<T: Decodable & Sendable>(
        _ path: String, query: [URLQueryItem]?, as type: T.Type
    ) async throws -> APIResponse<T> { throw URLError(.badURL) }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: (any AuthSessionRefresher)?) async {}
}
#endif
