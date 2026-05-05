#if canImport(UIKit)
import XCTest
@testable import Pos
@testable import Networking

/// Tests for ``GiftCardReloadViewModel``.
@MainActor
final class GiftCardReloadViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeActiveCard(balanceCents: Int = 10_000) -> GiftCard {
        GiftCard(id: 1, code: "ACTIVE01", balanceCents: balanceCents, currency: "USD", expiresAt: nil, active: true)
    }

    private func makeInactiveCard() -> GiftCard {
        GiftCard(id: 2, code: "INACTIVE", balanceCents: 0, currency: "USD", expiresAt: nil, active: false)
    }

    // MARK: - Initial state

    func test_initial_state_isIdle() {
        let vm = GiftCardReloadViewModel(api: MockAPIClient())
        XCTAssertEqual(vm.state, .idle)
    }

    func test_initial_card_isNil() {
        let vm = GiftCardReloadViewModel(api: MockAPIClient())
        XCTAssertNil(vm.card)
    }

    // MARK: - Validation

    func test_validationError_noCard() {
        let vm = GiftCardReloadViewModel(api: MockAPIClient())
        XCTAssertNotNil(vm.validationError)
    }

    func test_validationError_inactiveCard() {
        let vm = GiftCardReloadViewModel(api: MockAPIClient())
        vm.card = makeInactiveCard()
        vm.amountInput = "1000"
        XCTAssertNotNil(vm.validationError)
        XCTAssertTrue(vm.validationError!.lowercased().contains("active"))
    }

    func test_validationError_zeroAmount() {
        let vm = GiftCardReloadViewModel(api: MockAPIClient())
        vm.card = makeActiveCard()
        vm.amountInput = "0"
        XCTAssertNotNil(vm.validationError)
    }

    func test_validationError_exceedsMax() {
        let vm = GiftCardReloadViewModel(api: MockAPIClient())
        vm.card = makeActiveCard(balanceCents: 49_000)
        // Adding 2000 would bring total to 51000 > 50000 max.
        vm.amountInput = "2000"
        XCTAssertNotNil(vm.validationError)
    }

    func test_validationError_nil_whenValid() {
        let vm = GiftCardReloadViewModel(api: MockAPIClient())
        vm.card = makeActiveCard(balanceCents: 10_000)
        vm.amountInput = "5000" // 15000 total < 50000 max
        XCTAssertNil(vm.validationError)
    }

    func test_canReload_false_whenValidationFails() {
        let vm = GiftCardReloadViewModel(api: MockAPIClient())
        // No card set → validation error.
        XCTAssertFalse(vm.canReload)
    }

    func test_canReload_true_whenValid() {
        let vm = GiftCardReloadViewModel(api: MockAPIClient())
        vm.card = makeActiveCard()
        vm.amountInput = "1000"
        XCTAssertTrue(vm.canReload)
    }

    // MARK: - Max balance edge cases

    func test_validationError_exactlyAtMax_isValid() {
        let vm = GiftCardReloadViewModel(api: MockAPIClient())
        let maxBalance = GiftCardReloadViewModel.maxBalanceCents
        vm.card = makeActiveCard(balanceCents: 0)
        vm.amountInput = String(maxBalance) // = 50000
        XCTAssertNil(vm.validationError)
    }

    func test_validationError_oneOverMax_isInvalid() {
        let vm = GiftCardReloadViewModel(api: MockAPIClient())
        let maxBalance = GiftCardReloadViewModel.maxBalanceCents
        vm.card = makeActiveCard(balanceCents: 0)
        vm.amountInput = String(maxBalance + 1)
        XCTAssertNotNil(vm.validationError)
    }

    // MARK: - reload()

    func test_reload_success_setsSuccessState() async {
        let response = ReloadGiftCardResponse(newBalanceCents: 15_000)
        let api = MockAPIClient(reloadResult: .success(response))
        let vm = GiftCardReloadViewModel(api: api)
        vm.card = makeActiveCard(balanceCents: 10_000)
        vm.amountInput = "5000"
        await vm.reload()
        if case .success(let newBalance) = vm.state {
            XCTAssertEqual(newBalance, 15_000)
        } else {
            XCTFail("Expected .success, got \(vm.state)")
        }
    }

    func test_reload_failure_setsFailure() async {
        let api = MockAPIClient(reloadResult: .failure(MockAPIError()))
        let vm = GiftCardReloadViewModel(api: api)
        vm.card = makeActiveCard()
        vm.amountInput = "1000"
        await vm.reload()
        if case .failure = vm.state {
            // pass
        } else {
            XCTFail("Expected .failure, got \(vm.state)")
        }
    }

    func test_reload_invalidInput_doesNotCallAPI() async {
        var reloadCalled = false
        let api = MockAPIClient(reloadResult: .success(ReloadGiftCardResponse(newBalanceCents: 0)))
        api.onReload = { reloadCalled = true }
        let vm = GiftCardReloadViewModel(api: api)
        // No card set → canReload = false.
        await vm.reload()
        XCTAssertFalse(reloadCalled)
    }

    // MARK: - Reset

    func test_reset_clearsAmountAndState() async {
        let response = ReloadGiftCardResponse(newBalanceCents: 15_000)
        let api = MockAPIClient(reloadResult: .success(response))
        let vm = GiftCardReloadViewModel(api: api)
        vm.card = makeActiveCard()
        vm.amountInput = "5000"
        await vm.reload()
        vm.reset()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertEqual(vm.amountInput, "")
    }
}
#endif
