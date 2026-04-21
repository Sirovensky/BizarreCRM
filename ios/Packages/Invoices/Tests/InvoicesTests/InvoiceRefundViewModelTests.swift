import XCTest
@testable import Invoices
import Networking
import Core

// §7.4 InvoiceRefundViewModel tests — state transitions, validation, PIN gate.

@MainActor
final class InvoiceRefundViewModelTests: XCTestCase {

    private func makeSut(
        api: StubAPIClient = StubAPIClient(),
        totalPaidCents: Int = 10_000,
        lineItems: [RefundLineItem] = []
    ) -> InvoiceRefundViewModel {
        InvoiceRefundViewModel(api: api, invoiceId: 1, totalPaidCents: totalPaidCents, lineItems: lineItems)
    }

    // MARK: - Initial state

    func test_initialState_isIdle() {
        let vm = makeSut()
        guard case .idle = vm.state else {
            XCTFail("Expected .idle, got \(vm.state)")
            return
        }
    }

    func test_initialManualAmount_equalsTotalPaid() {
        let vm = makeSut(totalPaidCents: 7500)
        XCTAssertEqual(vm.manualAmountCents, 7500)
    }

    func test_initialReason_isReturn() {
        let vm = makeSut()
        XCTAssertEqual(vm.reason, .returnItem)
    }

    func test_initialUseLineItems_isFalse() {
        let vm = makeSut()
        XCTAssertFalse(vm.useLineItems)
    }

    // MARK: - effectiveAmountCents

    func test_effectiveAmount_manualMode_returnsManualCents() {
        let vm = makeSut(totalPaidCents: 5000)
        vm.useLineItems = false
        vm.manualAmountCents = 3000
        XCTAssertEqual(vm.effectiveAmountCents, 3000)
    }

    func test_effectiveAmount_lineItemMode_sumSelected() {
        let items = [
            RefundLineItem(id: 1, displayName: "Part A", totalCents: 1000, isSelected: true),
            RefundLineItem(id: 2, displayName: "Part B", totalCents: 2000, isSelected: false),
            RefundLineItem(id: 3, displayName: "Part C", totalCents: 500, isSelected: true)
        ]
        let vm = makeSut(totalPaidCents: 5000, lineItems: items)
        vm.useLineItems = true
        XCTAssertEqual(vm.effectiveAmountCents, 1500)
    }

    func test_effectiveAmount_lineItemMode_noSelection_returnsZero() {
        let items = [
            RefundLineItem(id: 1, displayName: "Part A", totalCents: 1000, isSelected: false)
        ]
        let vm = makeSut(totalPaidCents: 5000, lineItems: items)
        vm.useLineItems = true
        XCTAssertEqual(vm.effectiveAmountCents, 0)
    }

    // MARK: - requiresManagerPin

    func test_requiresManagerPin_falseBelow100Dollars() {
        let vm = makeSut(totalPaidCents: 5000)
        vm.manualAmountCents = 9_999
        XCTAssertFalse(vm.requiresManagerPin)
    }

    func test_requiresManagerPin_falseAtExactly100Dollars() {
        // Boundary: exactly $100 (10_000 cents) is NOT above threshold
        let vm = makeSut(totalPaidCents: 15_000)
        vm.manualAmountCents = 10_000
        XCTAssertFalse(vm.requiresManagerPin)
    }

    func test_requiresManagerPin_trueAboveThreshold() {
        let vm = makeSut(totalPaidCents: 15_000)
        vm.manualAmountCents = 10_001
        XCTAssertTrue(vm.requiresManagerPin)
    }

    func test_requiresManagerPin_trueAbove100Dollars() {
        let vm = makeSut(totalPaidCents: 20_000)
        vm.manualAmountCents = 15_000
        XCTAssertTrue(vm.requiresManagerPin)
    }

    // MARK: - isValid

    func test_isValid_trueWhenAmountPositiveAndWithinPaid() {
        let vm = makeSut(totalPaidCents: 5000)
        vm.manualAmountCents = 2500
        XCTAssertTrue(vm.isValid)
    }

    func test_isValid_falseWhenAmountZero() {
        let vm = makeSut(totalPaidCents: 5000)
        vm.manualAmountCents = 0
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_falseWhenAmountExceedsTotalPaid() {
        let vm = makeSut(totalPaidCents: 5000)
        vm.manualAmountCents = 6000
        XCTAssertFalse(vm.isValid)
    }

    // MARK: - submitRefund success

    func test_submitRefund_happyPath_transitionsToSuccess() async {
        let vm = makeSut(api: .refundSuccess(id: 77), totalPaidCents: 5000)
        await vm.submitRefund()
        guard case let .success(result) = vm.state else {
            XCTFail("Expected .success, got \(vm.state)")
            return
        }
        XCTAssertEqual(result.id, 77)
    }

    // MARK: - PIN gate

    func test_submitRefund_highAmount_triggersManagerPinPrompt() async {
        let vm = makeSut(api: .refundSuccess(), totalPaidCents: 20_000)
        vm.manualAmountCents = 15_000
        await vm.submitRefund()
        XCTAssertTrue(vm.showManagerPinPrompt)
        // Should NOT advance to success without pin
        guard case .idle = vm.state else {
            XCTFail("Expected .idle while waiting for PIN")
            return
        }
    }

    func test_submitWithPin_submitsPinAndSucceeds() async {
        let vm = makeSut(api: .refundSuccess(id: 88), totalPaidCents: 20_000)
        vm.manualAmountCents = 15_000
        await vm.submitWithPin("1234")
        XCTAssertEqual(vm.managerPin, "1234")
        XCTAssertFalse(vm.showManagerPinPrompt)
        guard case let .success(result) = vm.state else {
            XCTFail("Expected .success after PIN submission")
            return
        }
        XCTAssertEqual(result.id, 88)
    }

    // MARK: - AppError mapping

    func test_submitRefund_validationError_setsFieldErrors() async {
        let err = AppError.validation(fieldErrors: ["amount_cents": "Too large"])
        let vm = makeSut(api: .refundFailure(err), totalPaidCents: 5000)
        await vm.submitRefund()
        XCTAssertFalse(vm.fieldErrors.isEmpty)
    }

    func test_submitRefund_conflict_showsExceedsMessage() async {
        let err = AppError.conflict(reason: nil)
        let vm = makeSut(api: .refundFailure(err), totalPaidCents: 5000)
        await vm.submitRefund()
        guard case let .failed(msg) = vm.state else {
            XCTFail("Expected .failed"); return
        }
        XCTAssertTrue(msg.contains("exceeds"))
    }

    func test_submitRefund_forbidden_showsPermissionMessage() async {
        let err = AppError.forbidden(capability: nil)
        let vm = makeSut(api: .refundFailure(err), totalPaidCents: 5000)
        await vm.submitRefund()
        guard case let .failed(msg) = vm.state else {
            XCTFail("Expected .failed"); return
        }
        XCTAssertTrue(msg.lowercased().contains("permission"))
    }

    func test_submitRefund_rateLimited_withSeconds() async {
        let err = AppError.rateLimited(retryAfterSeconds: 60)
        let vm = makeSut(api: .refundFailure(err), totalPaidCents: 5000)
        await vm.submitRefund()
        guard case let .failed(msg) = vm.state else {
            XCTFail("Expected .failed"); return
        }
        XCTAssertTrue(msg.contains("60"))
    }

    // MARK: - manualAmountString setter

    func test_manualAmountString_setterUpdatesCents() {
        let vm = makeSut(totalPaidCents: 5000)
        vm.manualAmountString = "30.00"
        XCTAssertEqual(vm.manualAmountCents, 3000)
    }

    // MARK: - resetToIdle

    func test_resetToIdle_fromFailed_becomesIdle() async {
        let err = AppError.conflict(reason: nil)
        let vm = makeSut(api: .refundFailure(err), totalPaidCents: 5000)
        await vm.submitRefund()
        vm.resetToIdle()
        guard case .idle = vm.state else {
            XCTFail("Expected .idle after reset")
            return
        }
    }

    // MARK: - RefundReason enum

    func test_refundReasons_allHaveDisplayNames() {
        for reason in RefundReason.allCases {
            XCTAssertFalse(reason.displayName.isEmpty)
        }
    }

    func test_refundReasons_idEqualsRawValue() {
        for reason in RefundReason.allCases {
            XCTAssertEqual(reason.id, reason.rawValue)
        }
    }

    // MARK: - kRefundManagerPinThresholdCents constant

    func test_thresholdConstant_is10000Cents() {
        XCTAssertEqual(kRefundManagerPinThresholdCents, 10_000)
    }
}
