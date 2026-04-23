import XCTest
@testable import Invoices
import Networking
import Core

// §7.4 InvoiceRefundViewModel tests
// Endpoint: POST /api/v1/refunds (verified against refunds.routes.ts)
// Body: { invoice_id, customer_id, amount (dollars), type, reason, method }
// Covers: state transitions, validation, PIN gate, method/type selection, AppError mapping.

@MainActor
final class InvoiceRefundViewModelTests: XCTestCase {

    private func makeSut(
        api: StubAPIClient = StubAPIClient(),
        invoiceId: Int64 = 1,
        customerId: Int64 = 42,
        totalPaidCents: Int = 10_000,
        lineItems: [RefundLineItem] = []
    ) -> InvoiceRefundViewModel {
        InvoiceRefundViewModel(
            api: api,
            invoiceId: invoiceId,
            customerId: customerId,
            totalPaidCents: totalPaidCents,
            lineItems: lineItems
        )
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

    func test_initialRefundType_isRefund() {
        let vm = makeSut()
        XCTAssertEqual(vm.refundType, .refund)
    }

    func test_initialRefundMethod_isCard() {
        let vm = makeSut()
        XCTAssertEqual(vm.refundMethod, .card)
    }

    func test_initialUseLineItems_isFalse() {
        let vm = makeSut()
        XCTAssertFalse(vm.useLineItems)
    }

    func test_customerId_storedCorrectly() {
        let vm = makeSut(customerId: 99)
        XCTAssertEqual(vm.customerId, 99)
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
        let vm = makeSut(totalPaidCents: 15_000)
        vm.manualAmountCents = 10_000
        XCTAssertFalse(vm.requiresManagerPin)
    }

    func test_requiresManagerPin_trueAboveThreshold() {
        let vm = makeSut(totalPaidCents: 15_000)
        vm.manualAmountCents = 10_001
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

    // MARK: - Refund type selection

    func test_refundType_storeCredit_storedCorrectly() {
        let vm = makeSut()
        vm.refundType = .storeCredit
        XCTAssertEqual(vm.refundType, .storeCredit)
    }

    func test_refundType_creditNote_storedCorrectly() {
        let vm = makeSut()
        vm.refundType = .creditNote
        XCTAssertEqual(vm.refundType, .creditNote)
    }

    func test_refundMethod_cash_storedCorrectly() {
        let vm = makeSut()
        vm.refundMethod = .cash
        XCTAssertEqual(vm.refundMethod, .cash)
    }

    func test_refundMethod_giftCard_storedCorrectly() {
        let vm = makeSut()
        vm.refundMethod = .giftCard
        XCTAssertEqual(vm.refundMethod, .giftCard)
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

    // MARK: - submitRefund: full refund

    func test_submitRefund_fullAmount_succeeds() async {
        let vm = makeSut(api: .refundSuccess(id: 88), totalPaidCents: 10_000)
        vm.manualAmountCents = 10_000
        await vm.submitRefund()
        guard case .success = vm.state else {
            XCTFail("Expected .success for full refund")
            return
        }
    }

    // MARK: - submitRefund: partial refund

    func test_submitRefund_partialAmount_succeeds() async {
        let vm = makeSut(api: .refundSuccess(id: 99), totalPaidCents: 10_000)
        vm.manualAmountCents = 3_000
        await vm.submitRefund()
        guard case .success = vm.state else {
            XCTFail("Expected .success for partial refund")
            return
        }
    }

    // MARK: - PIN gate

    func test_submitRefund_highAmount_triggersManagerPinPrompt() async {
        let vm = makeSut(api: .refundSuccess(), totalPaidCents: 20_000)
        vm.manualAmountCents = 15_000
        await vm.submitRefund()
        XCTAssertTrue(vm.showManagerPinPrompt)
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
        let err = AppError.validation(fieldErrors: ["amount": "Too large"])
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
        XCTAssertTrue(msg.contains("exceeds") || msg.contains("available"))
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
        for r in RefundReason.allCases {
            XCTAssertFalse(r.displayName.isEmpty)
        }
    }

    func test_refundReasons_idEqualsRawValue() {
        for r in RefundReason.allCases {
            XCTAssertEqual(r.id, r.rawValue)
        }
    }

    // MARK: - RefundType enum

    func test_refundTypes_allHaveDisplayNames() {
        for t in RefundType.allCases {
            XCTAssertFalse(t.displayName.isEmpty, "RefundType \(t.rawValue) has no display name")
        }
    }

    func test_refundTypes_idEqualsRawValue() {
        for t in RefundType.allCases {
            XCTAssertEqual(t.id, t.rawValue)
        }
    }

    // MARK: - kRefundManagerPinThresholdCents constant

    func test_thresholdConstant_is10000Cents() {
        XCTAssertEqual(kRefundManagerPinThresholdCents, 10_000)
    }

    // MARK: - RefundLineItem immutability

    func test_refundLineItem_defaultRefundCentsEqualsTotal() {
        let item = RefundLineItem(id: 1, displayName: "Test", totalCents: 500)
        XCTAssertEqual(item.refundCents, 500)
    }

    func test_refundLineItem_defaultNotSelected() {
        let item = RefundLineItem(id: 1, displayName: "Test", totalCents: 500)
        XCTAssertFalse(item.isSelected)
    }
}
