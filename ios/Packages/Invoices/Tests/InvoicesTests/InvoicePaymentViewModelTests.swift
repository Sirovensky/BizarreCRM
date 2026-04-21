import XCTest
@testable import Invoices
import Networking
import Core

// §7.3 InvoicePaymentViewModel tests — state transitions, validation, AppError mapping.

@MainActor
final class InvoicePaymentViewModelTests: XCTestCase {

    private func makeSut(
        api: StubAPIClient = StubAPIClient(),
        invoiceId: Int64 = 1,
        balanceCents: Int = 5000
    ) -> InvoicePaymentViewModel {
        InvoicePaymentViewModel(api: api, invoiceId: invoiceId, balanceCents: balanceCents)
    }

    // MARK: - Initial state

    func test_initialState_isIdle() {
        let vm = makeSut()
        guard case .idle = vm.state else {
            XCTFail("Expected .idle, got \(vm.state)")
            return
        }
    }

    func test_initialAmountCents_equalsBalance() {
        let vm = makeSut(balanceCents: 12345)
        XCTAssertEqual(vm.amountCents, 12345)
    }

    func test_initialAmountString_formatsCorrectly() {
        let vm = makeSut(balanceCents: 5050)
        XCTAssertEqual(vm.amountString, "50.50")
    }

    func test_defaultTender_isCash() {
        let vm = makeSut()
        XCTAssertEqual(vm.tender, .cash)
    }

    // MARK: - isValid

    func test_isValid_trueWhenAmountPositive() {
        let vm = makeSut(balanceCents: 1000)
        vm.amountCents = 500
        XCTAssertTrue(vm.isValid)
    }

    func test_isValid_falseWhenAmountZero() {
        let vm = makeSut(balanceCents: 1000)
        vm.amountCents = 0
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_falseWhenAmountNegative() {
        let vm = makeSut(balanceCents: 1000)
        vm.amountCents = -1
        XCTAssertFalse(vm.isValid)
    }

    // MARK: - isPartialPayment

    func test_isPartialPayment_trueWhenAmountLessThanBalance() {
        let vm = makeSut(balanceCents: 5000)
        vm.amountCents = 2500
        XCTAssertTrue(vm.isPartialPayment)
    }

    func test_isPartialPayment_falseWhenAmountEqualsBalance() {
        let vm = makeSut(balanceCents: 5000)
        vm.amountCents = 5000
        XCTAssertFalse(vm.isPartialPayment)
    }

    func test_isPartialPayment_falseWhenAmountExceedsBalance() {
        let vm = makeSut(balanceCents: 5000)
        vm.amountCents = 6000
        XCTAssertFalse(vm.isPartialPayment)
    }

    // MARK: - amountString setter

    func test_amountString_setterUpdatesCents() {
        let vm = makeSut(balanceCents: 5000)
        vm.amountString = "25.00"
        XCTAssertEqual(vm.amountCents, 2500)
    }

    func test_amountString_handlesInvalidInput() {
        let vm = makeSut(balanceCents: 5000)
        let previous = vm.amountCents
        vm.amountString = "abc"
        // Non-numeric input should not crash and may leave previous or zero
        XCTAssertTrue(vm.amountCents >= 0)
        _ = previous // suppress unused warning
    }

    // MARK: - applyPayment success

    func test_applyPayment_happyPath_transitionsToSuccess() async {
        let vm = makeSut(api: .paymentSuccess(id: 42), balanceCents: 5000)
        await vm.applyPayment()
        guard case let .success(result) = vm.state else {
            XCTFail("Expected .success, got \(vm.state)")
            return
        }
        XCTAssertEqual(result.id, 42)
    }

    // MARK: - applyPayment invalid amount

    func test_applyPayment_invalidAmount_setsFailed() async {
        let vm = makeSut(balanceCents: 5000)
        vm.amountCents = 0
        await vm.applyPayment()
        guard case .failed = vm.state else {
            XCTFail("Expected .failed, got \(vm.state)")
            return
        }
    }

    // MARK: - AppError mapping: validation

    func test_applyPayment_validationError_setsFailed() async {
        let err = AppError.validation(fieldErrors: ["amount": "Amount exceeds balance"])
        let vm = makeSut(api: .paymentFailure(err), balanceCents: 5000)
        await vm.applyPayment()
        guard case let .failed(msg) = vm.state else {
            XCTFail("Expected .failed"); return
        }
        XCTAssertTrue(msg.contains("Amount exceeds balance"))
    }

    func test_applyPayment_validationError_setsFieldErrors() async {
        let err = AppError.validation(fieldErrors: ["amount": "Too high"])
        let vm = makeSut(api: .paymentFailure(err), balanceCents: 5000)
        await vm.applyPayment()
        XCTAssertFalse(vm.fieldErrors.isEmpty)
    }

    // MARK: - AppError mapping: conflict

    func test_applyPayment_conflict_showsAlreadyPaidMessage() async {
        let err = AppError.conflict(reason: nil)
        let vm = makeSut(api: .paymentFailure(err), balanceCents: 5000)
        await vm.applyPayment()
        guard case let .failed(msg) = vm.state else {
            XCTFail("Expected .failed"); return
        }
        XCTAssertEqual(msg, "Invoice already paid.")
    }

    // MARK: - AppError mapping: rateLimited

    func test_applyPayment_rateLimited_withSeconds_showsWaitMessage() async {
        let err = AppError.rateLimited(retryAfterSeconds: 30)
        let vm = makeSut(api: .paymentFailure(err), balanceCents: 5000)
        await vm.applyPayment()
        guard case let .failed(msg) = vm.state else {
            XCTFail("Expected .failed"); return
        }
        XCTAssertTrue(msg.contains("30"))
    }

    func test_applyPayment_rateLimited_withoutSeconds_showsGenericMessage() async {
        let err = AppError.rateLimited(retryAfterSeconds: nil)
        let vm = makeSut(api: .paymentFailure(err), balanceCents: 5000)
        await vm.applyPayment()
        guard case let .failed(msg) = vm.state else {
            XCTFail("Expected .failed"); return
        }
        XCTAssertTrue(msg.contains("Too many"))
    }

    // MARK: - resetToIdle

    func test_resetToIdle_fromFailed_becomesIdle() async {
        let err = AppError.conflict(reason: nil)
        let vm = makeSut(api: .paymentFailure(err), balanceCents: 5000)
        await vm.applyPayment()
        vm.resetToIdle()
        guard case .idle = vm.state else {
            XCTFail("Expected .idle after reset, got \(vm.state)")
            return
        }
    }

    func test_resetToIdle_fromSuccess_doesNothing() async {
        let vm = makeSut(api: .paymentSuccess(), balanceCents: 5000)
        await vm.applyPayment()
        vm.resetToIdle()
        // State should still be .success since reset only clears .failed
        guard case .success = vm.state else {
            XCTFail("Expected .success to remain")
            return
        }
    }

    // MARK: - Tender enum

    func test_tender_allCasesHaveDisplayNames() {
        for tender in InvoiceTender.allCases {
            XCTAssertFalse(tender.displayName.isEmpty, "Tender \(tender.rawValue) has no display name")
        }
    }

    func test_tender_idEqualsRawValue() {
        for tender in InvoiceTender.allCases {
            XCTAssertEqual(tender.id, tender.rawValue)
        }
    }
}
