#if canImport(UIKit)
import XCTest
@testable import Pos
@testable import Networking

/// Tests for ``GiftCardTransferViewModel``.
@MainActor
final class GiftCardTransferViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeCard(
        id: Int64,
        code: String,
        balanceCents: Int = 10_000,
        active: Bool = true
    ) -> GiftCard {
        GiftCard(id: id, code: code, balanceCents: balanceCents, currency: "USD", expiresAt: nil, active: active)
    }

    // MARK: - Initial state

    func test_initial_state_isIdle() {
        let vm = GiftCardTransferViewModel(api: MockAPIClient())
        XCTAssertEqual(vm.state, .idle)
    }

    // MARK: - Validation

    func test_validationError_noCards() {
        let vm = GiftCardTransferViewModel(api: MockAPIClient())
        XCTAssertNotNil(vm.validationError)
    }

    func test_validationError_onlySourceCard() async {
        let source = makeCard(id: 1, code: "SRC001")
        let api = MockAPIClient(lookupResult: .success(source))
        let vm = GiftCardTransferViewModel(api: api)
        vm.sourceCodeInput = source.code
        await vm.lookupSource()
        vm.amountInput = "1000"
        XCTAssertNotNil(vm.validationError)
        XCTAssertTrue(vm.validationError!.lowercased().contains("target"))
    }

    func test_validationError_inactiveSource() async {
        let source = makeCard(id: 1, code: "SRC001", active: false)
        let target = makeCard(id: 2, code: "TGT001")
        let api = MockAPIClient(lookupResults: [source, target])
        let vm = GiftCardTransferViewModel(api: api)
        vm.sourceCodeInput = source.code
        await vm.lookupSource()
        vm.targetCodeInput = target.code
        await vm.lookupTarget()
        vm.amountInput = "1000"
        XCTAssertNotNil(vm.validationError)
        XCTAssertTrue(vm.validationError!.lowercased().contains("active"))
    }

    func test_validationError_amountExceedsSourceBalance() async {
        let source = makeCard(id: 1, code: "SRC001", balanceCents: 5_000)
        let target = makeCard(id: 2, code: "TGT001")
        let api = MockAPIClient(lookupResults: [source, target])
        let vm = GiftCardTransferViewModel(api: api)
        vm.sourceCodeInput = source.code
        await vm.lookupSource()
        vm.targetCodeInput = target.code
        await vm.lookupTarget()
        vm.amountInput = "10000" // 10000 > 5000
        XCTAssertNotNil(vm.validationError)
    }

    func test_validationError_nil_whenValid() async {
        let source = makeCard(id: 1, code: "SRC001", balanceCents: 10_000)
        let target = makeCard(id: 2, code: "TGT001")
        let api = MockAPIClient(lookupResults: [source, target])
        let vm = GiftCardTransferViewModel(api: api)
        vm.sourceCodeInput = source.code
        await vm.lookupSource()
        vm.targetCodeInput = target.code
        await vm.lookupTarget()
        vm.amountInput = "5000"
        XCTAssertNil(vm.validationError)
    }

    // MARK: - Lookup

    func test_lookupSource_failure_setsFailure() async {
        let api = MockAPIClient(lookupResult: .failure(MockAPIError()))
        let vm = GiftCardTransferViewModel(api: api)
        vm.sourceCodeInput = "BAD"
        await vm.lookupSource()
        if case .failure = vm.state {
            // pass
        } else {
            XCTFail("Expected .failure, got \(vm.state)")
        }
    }

    func test_lookupTarget_failure_setsFailure() async {
        let source = makeCard(id: 1, code: "SRC001")
        let api = MockAPIClient(lookupResults: [source], lookupFailAfterIndex: 1)
        let vm = GiftCardTransferViewModel(api: api)
        vm.sourceCodeInput = source.code
        await vm.lookupSource()
        vm.targetCodeInput = "BAD"
        await vm.lookupTarget()
        if case .failure = vm.state {
            // pass
        } else {
            XCTFail("Expected .failure, got \(vm.state)")
        }
    }

    // MARK: - Transfer

    func test_transfer_success_setsSuccessState() async {
        let source = makeCard(id: 1, code: "SRC001", balanceCents: 10_000)
        let target = makeCard(id: 2, code: "TGT001", balanceCents: 5_000)
        let transferResponse = TransferGiftCardResponse(
            sourceBalanceCents: 7_000,
            targetBalanceCents: 8_000
        )
        let api = MockAPIClient(lookupResults: [source, target], transferResult: .success(transferResponse))
        let vm = GiftCardTransferViewModel(api: api)
        vm.sourceCodeInput = source.code
        await vm.lookupSource()
        vm.targetCodeInput = target.code
        await vm.lookupTarget()
        vm.amountInput = "3000"
        await vm.transfer()
        if case .success(let resp) = vm.state {
            XCTAssertEqual(resp.sourceBalanceCents, 7_000)
            XCTAssertEqual(resp.targetBalanceCents, 8_000)
        } else {
            XCTFail("Expected .success, got \(vm.state)")
        }
    }

    func test_transfer_failure_setsFailure() async {
        let source = makeCard(id: 1, code: "SRC001", balanceCents: 10_000)
        let target = makeCard(id: 2, code: "TGT001")
        let api = MockAPIClient(lookupResults: [source, target], transferResult: .failure(MockAPIError()))
        let vm = GiftCardTransferViewModel(api: api)
        vm.sourceCodeInput = source.code
        await vm.lookupSource()
        vm.targetCodeInput = target.code
        await vm.lookupTarget()
        vm.amountInput = "3000"
        await vm.transfer()
        if case .failure = vm.state {
            // pass
        } else {
            XCTFail("Expected .failure, got \(vm.state)")
        }
    }

    // MARK: - Reset

    func test_reset_clearsAllFields() async {
        let source = makeCard(id: 1, code: "SRC001", balanceCents: 10_000)
        let target = makeCard(id: 2, code: "TGT001")
        let api = MockAPIClient(lookupResults: [source, target])
        let vm = GiftCardTransferViewModel(api: api)
        vm.sourceCodeInput = source.code
        await vm.lookupSource()
        vm.targetCodeInput = target.code
        await vm.lookupTarget()
        vm.amountInput = "1000"
        vm.reset()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertNil(vm.sourceCard)
        XCTAssertNil(vm.targetCard)
        XCTAssertEqual(vm.amountInput, "")
        XCTAssertEqual(vm.sourceCodeInput, "")
        XCTAssertEqual(vm.targetCodeInput, "")
    }
}
#endif
