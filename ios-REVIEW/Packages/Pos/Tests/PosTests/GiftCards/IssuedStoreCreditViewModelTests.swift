import XCTest
@testable import Pos

/// §40.2 — Unit tests for `IssuedStoreCreditViewModel`.
/// No UIKit, no network — logic only.
@MainActor
final class IssuedStoreCreditViewModelTests: XCTestCase {

    private func makeSUT(
        prefillAmountCents: Int? = nil,
        prefillInvoiceId: Int64? = nil
    ) -> IssuedStoreCreditViewModel {
        IssuedStoreCreditViewModel(
            customerId: 42,
            api: nil,
            prefillAmountCents: prefillAmountCents,
            prefillInvoiceId: prefillInvoiceId
        )
    }

    // MARK: - Initial state

    func test_initial_state_isIdle() {
        let vm = makeSUT()
        XCTAssertEqual(vm.state, .idle)
    }

    func test_initial_amountText_emptyWhenNoPrefill() {
        let vm = makeSUT()
        XCTAssertEqual(vm.amountText, "")
    }

    func test_initial_amountText_filledWhenPrefill() {
        let vm = makeSUT(prefillAmountCents: 3500)
        XCTAssertFalse(vm.amountText.isEmpty)
    }

    func test_initial_reasonCategory_isReturnRefund() {
        let vm = makeSUT()
        XCTAssertEqual(vm.reasonCategory, .returnRefund)
    }

    func test_initial_managerApproved_isFalse() {
        let vm = makeSUT()
        XCTAssertFalse(vm.managerApproved)
    }

    // MARK: - amountCents parsing

    func test_amountCents_emptyText_returnsZero() {
        let vm = makeSUT()
        vm.amountText = ""
        XCTAssertEqual(vm.amountCents, 0)
    }

    func test_amountCents_decimalInput() {
        let vm = makeSUT()
        vm.amountText = "10.50"
        XCTAssertEqual(vm.amountCents, 1050)
    }

    func test_amountCents_integerInput() {
        let vm = makeSUT()
        vm.amountText = "25"
        XCTAssertEqual(vm.amountCents, 2500)
    }

    func test_amountCents_zeroDecimal_returnsZero() {
        let vm = makeSUT()
        vm.amountText = "0.00"
        XCTAssertEqual(vm.amountCents, 0)
    }

    func test_amountCents_negativeInput_returnsZero() {
        let vm = makeSUT()
        vm.amountText = "-5.00"
        XCTAssertEqual(vm.amountCents, 0)
    }

    func test_amountCents_invalidText_returnsZero() {
        let vm = makeSUT()
        vm.amountText = "abc"
        XCTAssertEqual(vm.amountCents, 0)
    }

    func test_amountCents_prefillRoundtrip() {
        let vm = makeSUT(prefillAmountCents: 3500)
        XCTAssertEqual(vm.amountCents, 3500)
    }

    // MARK: - requiresManagerPin

    func test_requiresManagerPin_belowThreshold_false() {
        let vm = makeSUT()
        vm.amountText = "24.99"
        XCTAssertFalse(vm.requiresManagerPin)
    }

    func test_requiresManagerPin_atThreshold_false() {
        let vm = makeSUT()
        vm.amountText = "25.00"  // exactly 2500¢ — not above
        XCTAssertFalse(vm.requiresManagerPin)
    }

    func test_requiresManagerPin_aboveThreshold_true() {
        let vm = makeSUT()
        vm.amountText = "25.01"
        XCTAssertTrue(vm.requiresManagerPin)
    }

    func test_pinThreshold_is2500Cents() {
        let vm = makeSUT()
        XCTAssertEqual(vm.pinThresholdCents, 2_500)
    }

    // MARK: - canIssue

    func test_canIssue_zeroAmount_false() {
        let vm = makeSUT()
        vm.amountText = ""
        XCTAssertFalse(vm.canIssue)
    }

    func test_canIssue_positiveAmount_true() {
        let vm = makeSUT()
        vm.amountText = "10.00"
        XCTAssertTrue(vm.canIssue)
    }

    func test_canIssue_whileIssuing_false() {
        let vm = makeSUT()
        vm.amountText = "10.00"
        vm.state = .issuing
        XCTAssertFalse(vm.canIssue)
    }

    // MARK: - issue — no api

    func test_issue_nilApi_setsErrorMessage() async {
        let vm = makeSUT()
        vm.amountText = "10.00"
        await vm.issue()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.errorMessage!.lowercased().contains("server") ||
                      vm.errorMessage!.lowercased().contains("connected"))
    }

    func test_issue_zeroAmountNilApi_setsErrorMessage() async {
        let vm = makeSUT()
        vm.amountText = ""
        await vm.issue()
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - ReasonCategory

    func test_allReasonCategories_haveLabels() {
        for cat in IssuedStoreCreditViewModel.ReasonCategory.allCases {
            XCTAssertFalse(cat.label.isEmpty, "\(cat) has empty label")
        }
    }

    func test_allReasonCategories_haveWireValues() {
        for cat in IssuedStoreCreditViewModel.ReasonCategory.allCases {
            XCTAssertFalse(cat.wireValue.isEmpty)
            XCTAssertEqual(cat.wireValue, cat.rawValue)
        }
    }

    func test_reasonCategory_count() {
        XCTAssertEqual(IssuedStoreCreditViewModel.ReasonCategory.allCases.count, 4)
    }

    // MARK: - State equatable

    func test_state_equatable_issued() {
        let a = IssuedStoreCreditViewModel.State.issued(100)
        let b = IssuedStoreCreditViewModel.State.issued(100)
        XCTAssertEqual(a, b)
    }

    func test_state_equatable_differentAmounts_notEqual() {
        let a = IssuedStoreCreditViewModel.State.issued(100)
        let b = IssuedStoreCreditViewModel.State.issued(200)
        XCTAssertNotEqual(a, b)
    }
}
