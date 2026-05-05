#if canImport(UIKit)
import XCTest
@testable import Pos
@testable import Networking

/// Tests for ``GiftCardSellViewModel``.
///
/// The API is stubbed via `MockAPIClient` so no network required.
@MainActor
final class GiftCardSellViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeCard(
        id: Int64 = 1,
        code: String = "ABCD1234",
        balanceCents: Int = 5000,
        active: Bool = true
    ) -> GiftCard {
        GiftCard(id: id, code: code, balanceCents: balanceCents, currency: "USD", expiresAt: nil, active: active)
    }

    private func makeUnissuedCard() -> GiftCard {
        // Server returns status != "active" and zero balance for unissued cards.
        GiftCard(id: 99, code: "UNISSUED1", balanceCents: 0, currency: "USD", expiresAt: nil, active: false)
    }

    // MARK: - Initial state

    func test_initial_state_isIdle() {
        let vm = GiftCardSellViewModel(api: MockAPIClient())
        XCTAssertEqual(vm.state, .idle)
    }

    func test_initial_sellMode_isPhysical() {
        let vm = GiftCardSellViewModel(api: MockAPIClient())
        XCTAssertEqual(vm.sellMode, .physical)
    }

    // MARK: - Physical path — lookup

    func test_lookupCard_emptyInput_doesNothing() async {
        let vm = GiftCardSellViewModel(api: MockAPIClient())
        vm.barcodeInput = ""
        await vm.lookupCard()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertNil(vm.scannedCard)
    }

    func test_lookupCard_success_populatesScannedCard() async {
        let card = makeCard()
        let api = MockAPIClient(lookupResult: .success(card))
        let vm = GiftCardSellViewModel(api: api)
        vm.barcodeInput = card.code
        await vm.lookupCard()
        XCTAssertEqual(vm.scannedCard, card)
        XCTAssertEqual(vm.state, .idle)
    }

    func test_lookupCard_failure_setsFailureState() async {
        let api = MockAPIClient(lookupResult: .failure(MockAPIError()))
        let vm = GiftCardSellViewModel(api: api)
        vm.barcodeInput = "BADCODE"
        await vm.lookupCard()
        if case .failure = vm.state {
            // pass
        } else {
            XCTFail("Expected .failure after lookup error, got \(vm.state)")
        }
    }

    // MARK: - isUnissued

    func test_isUnissued_false_whenNoCard() {
        let vm = GiftCardSellViewModel(api: MockAPIClient())
        XCTAssertFalse(vm.isUnissued)
    }

    func test_isUnissued_false_whenActiveCard() async {
        let card = makeCard(active: true)
        let api = MockAPIClient(lookupResult: .success(card))
        let vm = GiftCardSellViewModel(api: api)
        vm.barcodeInput = card.code
        await vm.lookupCard()
        XCTAssertFalse(vm.isUnissued)
    }

    func test_isUnissued_true_whenInactiveZeroBalance() async {
        let card = makeUnissuedCard()
        let api = MockAPIClient(lookupResult: .success(card))
        let vm = GiftCardSellViewModel(api: api)
        vm.barcodeInput = card.code
        await vm.lookupCard()
        XCTAssertTrue(vm.isUnissued)
    }

    // MARK: - Physical path — activate

    func test_activateCard_success_setsSentState() async {
        let unissued = makeUnissuedCard()
        let activated = makeCard(id: unissued.id, code: unissued.code, balanceCents: 2500, active: true)
        let api = MockAPIClient(lookupResult: .success(unissued), activateResult: .success(activated))
        let vm = GiftCardSellViewModel(api: api)
        vm.barcodeInput = unissued.code
        await vm.lookupCard()
        vm.activationAmountInput = "2500"
        await vm.activateCard()
        if case .sent(let card) = vm.state {
            XCTAssertEqual(card.balanceCents, 2500)
        } else {
            XCTFail("Expected .sent, got \(vm.state)")
        }
    }

    func test_canActivate_false_whenAmountZero() async {
        let unissued = makeUnissuedCard()
        let api = MockAPIClient(lookupResult: .success(unissued))
        let vm = GiftCardSellViewModel(api: api)
        vm.barcodeInput = unissued.code
        await vm.lookupCard()
        vm.activationAmountInput = "0"
        XCTAssertFalse(vm.canActivate)
    }

    func test_canActivate_true_whenUnissuedAndPositiveAmount() async {
        let unissued = makeUnissuedCard()
        let api = MockAPIClient(lookupResult: .success(unissued))
        let vm = GiftCardSellViewModel(api: api)
        vm.barcodeInput = unissued.code
        await vm.lookupCard()
        vm.activationAmountInput = "1000"
        XCTAssertTrue(vm.canActivate)
    }

    // MARK: - Virtual path

    func test_canSendVirtual_false_withEmptyFields() {
        let vm = GiftCardSellViewModel(api: MockAPIClient())
        vm.sellMode = .virtual
        XCTAssertFalse(vm.canSendVirtual)
    }

    func test_canSendVirtual_false_withInvalidEmail() {
        let vm = GiftCardSellViewModel(api: MockAPIClient())
        vm.sellMode = .virtual
        vm.recipientName = "Alice"
        vm.recipientEmail = "not-an-email"
        vm.virtualAmountInput = "5000"
        XCTAssertFalse(vm.canSendVirtual)
    }

    func test_canSendVirtual_true_withValidFields() {
        let vm = GiftCardSellViewModel(api: MockAPIClient())
        vm.sellMode = .virtual
        vm.recipientName = "Alice"
        vm.recipientEmail = "alice@example.com"
        vm.virtualAmountInput = "5000"
        XCTAssertTrue(vm.canSendVirtual)
    }

    func test_sendVirtualCard_success_setsSentState() async {
        let card = makeCard(balanceCents: 5000)
        let api = MockAPIClient(createVirtualResult: .success(card))
        let vm = GiftCardSellViewModel(api: api)
        vm.sellMode = .virtual
        vm.recipientName = "Alice"
        vm.recipientEmail = "alice@example.com"
        vm.virtualAmountInput = "5000"
        await vm.sendVirtualCard()
        if case .sent(let c) = vm.state {
            XCTAssertEqual(c.balanceCents, 5000)
        } else {
            XCTFail("Expected .sent, got \(vm.state)")
        }
    }

    func test_sendVirtualCard_failure_setsFailure() async {
        let api = MockAPIClient(createVirtualResult: .failure(MockAPIError()))
        let vm = GiftCardSellViewModel(api: api)
        vm.sellMode = .virtual
        vm.recipientName = "Alice"
        vm.recipientEmail = "alice@example.com"
        vm.virtualAmountInput = "5000"
        await vm.sendVirtualCard()
        if case .failure = vm.state {
            // pass
        } else {
            XCTFail("Expected .failure, got \(vm.state)")
        }
    }

    // MARK: - Reset

    func test_reset_clearsAllFields() async {
        let card = makeCard()
        let api = MockAPIClient(lookupResult: .success(card))
        let vm = GiftCardSellViewModel(api: api)
        vm.barcodeInput = "CODE"
        await vm.lookupCard()
        vm.activationAmountInput = "1000"
        vm.reset()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertEqual(vm.barcodeInput, "")
        XCTAssertNil(vm.scannedCard)
        XCTAssertEqual(vm.activationAmountInput, "")
        XCTAssertEqual(vm.recipientName, "")
        XCTAssertEqual(vm.recipientEmail, "")
        XCTAssertEqual(vm.virtualAmountInput, "")
    }
}
#endif
