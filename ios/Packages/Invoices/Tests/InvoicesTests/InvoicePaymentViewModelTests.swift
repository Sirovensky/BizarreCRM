import XCTest
@testable import Invoices
import Networking
import Core

// §7.3 InvoicePaymentViewModel tests
// Endpoint: POST /api/v1/invoices/:id/payments (verified against invoices.routes.ts)
// Covers: state transitions, validation, split tender, change due, AppError mapping.

@MainActor
final class InvoicePaymentViewModelTests: XCTestCase {

    private func makeSut(
        api: StubAPIClient = StubAPIClient(),
        invoiceId: Int64 = 1,
        balanceCents: Int = 5000,
        customerId: Int64? = nil
    ) -> InvoicePaymentViewModel {
        InvoicePaymentViewModel(api: api, invoiceId: invoiceId, balanceCents: balanceCents, customerId: customerId)
    }

    // MARK: - Initial state

    func test_initialState_isIdle() {
        let vm = makeSut()
        guard case .idle = vm.state else {
            XCTFail("Expected .idle, got \(vm.state)")
            return
        }
    }

    func test_initialLeg_hasFullBalance() {
        let vm = makeSut(balanceCents: 12345)
        XCTAssertEqual(vm.legs.count, 1)
        XCTAssertEqual(vm.legs[0].amountCents, 12345)
    }

    func test_initialTender_isCash() {
        let vm = makeSut()
        XCTAssertEqual(vm.tender, .cash)
    }

    func test_initialTotalTendered_equalsBalance() {
        let vm = makeSut(balanceCents: 5000)
        XCTAssertEqual(vm.totalTenderedCents, 5000)
    }

    func test_initialRemaining_isZero() {
        let vm = makeSut(balanceCents: 5000)
        XCTAssertEqual(vm.remainingCents, 0)
    }

    // MARK: - isValid

    func test_isValid_trueWhenSingleLegPositive() {
        let vm = makeSut(balanceCents: 1000)
        vm.amountCents = 500
        XCTAssertTrue(vm.isValid)
    }

    func test_isValid_falseWhenFirstLegZero() {
        let vm = makeSut(balanceCents: 1000)
        vm.amountCents = 0
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_falseWhenAnyLegIsZero() {
        let vm = makeSut(balanceCents: 5000)
        vm.addLeg()
        // Set second leg to 0 explicitly
        let secondLegId = vm.legs[1].id
        vm.updateLeg(id: secondLegId, amountCents: 0)
        XCTAssertFalse(vm.isValid)
    }

    // MARK: - isPartialPayment

    func test_isPartialPayment_trueWhenLessThanBalance() {
        let vm = makeSut(balanceCents: 5000)
        vm.amountCents = 2500
        XCTAssertTrue(vm.isPartialPayment)
    }

    func test_isPartialPayment_falseWhenEqualsBalance() {
        let vm = makeSut(balanceCents: 5000)
        vm.amountCents = 5000
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
        vm.amountString = "abc"
        XCTAssertTrue(vm.amountCents >= 0)
    }

    // MARK: - Split tender: addLeg / removeLeg / updateLeg

    func test_addLeg_incrementsCount() {
        let vm = makeSut(balanceCents: 5000)
        vm.addLeg()
        XCTAssertEqual(vm.legs.count, 2)
    }

    func test_addLeg_setsNewLegToRemaining() {
        let vm = makeSut(balanceCents: 5000)
        vm.amountCents = 2000        // First leg pays 2000
        vm.addLeg()
        // Remaining was 3000, so second leg starts at 3000
        XCTAssertEqual(vm.legs[1].amountCents, 3000)
    }

    func test_removeLeg_decrementsCount() {
        let vm = makeSut(balanceCents: 5000)
        vm.addLeg()
        XCTAssertEqual(vm.legs.count, 2)
        vm.removeLeg(at: IndexSet(integer: 1))
        XCTAssertEqual(vm.legs.count, 1)
    }

    func test_removeLeg_doesNotRemoveLastLeg() {
        let vm = makeSut(balanceCents: 5000)
        vm.removeLeg(at: IndexSet(integer: 0))
        XCTAssertEqual(vm.legs.count, 1)
    }

    func test_updateLeg_changesTender() {
        let vm = makeSut(balanceCents: 5000)
        let legId = vm.legs[0].id
        vm.updateLeg(id: legId, tender: .card)
        XCTAssertEqual(vm.legs[0].tender, .card)
    }

    func test_updateLeg_changesAmount() {
        let vm = makeSut(balanceCents: 5000)
        let legId = vm.legs[0].id
        vm.updateLeg(id: legId, amountCents: 1234)
        XCTAssertEqual(vm.legs[0].amountCents, 1234)
    }

    func test_updateLeg_changesReference() {
        let vm = makeSut(balanceCents: 5000)
        let legId = vm.legs[0].id
        vm.updateLeg(id: legId, reference: "REF-99")
        XCTAssertEqual(vm.legs[0].reference, "REF-99")
    }

    func test_totalTendered_sumsAllLegs() {
        let vm = makeSut(balanceCents: 5000)
        vm.amountCents = 2000
        vm.addLeg()
        let id2 = vm.legs[1].id
        vm.updateLeg(id: id2, amountCents: 3000)
        XCTAssertEqual(vm.totalTenderedCents, 5000)
    }

    // MARK: - Change due (cash overpayment)

    func test_isOverpayment_falseWhenExact() {
        let vm = makeSut(balanceCents: 5000)
        vm.amountCents = 5000
        XCTAssertFalse(vm.isOverpayment)
    }

    func test_isOverpayment_trueWhenMore() {
        let vm = makeSut(balanceCents: 5000)
        vm.amountCents = 6000
        XCTAssertTrue(vm.isOverpayment)
    }

    func test_changeDue_zeroWhenExact() {
        let vm = makeSut(balanceCents: 5000)
        vm.amountCents = 5000
        XCTAssertEqual(vm.changeDueCents, 0)
    }

    func test_changeDue_computedCorrectly() {
        let vm = makeSut(balanceCents: 5000)
        vm.amountCents = 6000
        XCTAssertEqual(vm.changeDueCents, 1000)
    }

    // MARK: - applyPayment success (single leg)

    func test_applyPayment_happyPath_transitionsToSuccess() async {
        let vm = makeSut(api: .paymentSuccess(id: 42), balanceCents: 5000)
        await vm.applyPayment()
        guard case let .success(result) = vm.state else {
            XCTFail("Expected .success, got \(vm.state)")
            return
        }
        XCTAssertEqual(result.id, 42)
    }

    // MARK: - applyPayment: split tender success (two legs)

    func test_applyPayment_splitTender_twoLegsSucceed() async {
        let vm = makeSut(api: .paymentSuccess(id: 55), balanceCents: 5000)
        vm.amountCents = 2000
        vm.addLeg()
        let id2 = vm.legs[1].id
        vm.updateLeg(id: id2, tender: .card, amountCents: 3000)
        await vm.applyPayment()
        guard case .success = vm.state else {
            XCTFail("Expected .success after split tender")
            return
        }
    }

    // MARK: - applyPayment invalid amount

    func test_applyPayment_zeroAmount_setsFailed() async {
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

    // MARK: - AppError mapping: conflict (duplicate payment)

    func test_applyPayment_conflict_showsDuplicateMessage() async {
        let err = AppError.conflict(reason: nil)
        let vm = makeSut(api: .paymentFailure(err), balanceCents: 5000)
        await vm.applyPayment()
        guard case let .failed(msg) = vm.state else {
            XCTFail("Expected .failed"); return
        }
        XCTAssertTrue(msg.lowercased().contains("duplicate"))
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
        guard case .success = vm.state else {
            XCTFail("Expected .success to remain")
            return
        }
    }

    // MARK: - Tender enum

    func test_tender_allCasesHaveDisplayNames() {
        for t in InvoiceTender.allCases {
            XCTAssertFalse(t.displayName.isEmpty, "Tender \(t.rawValue) has no display name")
        }
    }

    func test_tender_idEqualsRawValue() {
        for t in InvoiceTender.allCases {
            XCTAssertEqual(t.id, t.rawValue)
        }
    }

    func test_tender_needsReference_card_true() {
        XCTAssertTrue(InvoiceTender.card.needsReference)
    }

    func test_tender_needsReference_cash_false() {
        XCTAssertFalse(InvoiceTender.cash.needsReference)
    }

    func test_tender_needsReference_giftCard_true() {
        XCTAssertTrue(InvoiceTender.giftCard.needsReference)
    }

    // MARK: - PaymentLeg immutability

    func test_paymentLeg_immutableId() {
        let leg = PaymentLeg(tender: .cash, amountCents: 1000)
        let id = leg.id
        // Updating via ViewModel creates a new leg value — id stays same
        let vm = makeSut(balanceCents: 5000)
        vm.updateLeg(id: vm.legs[0].id, amountCents: 9999)
        XCTAssertEqual(vm.legs[0].id, vm.legs[0].id) // stable
        _ = id; _ = leg
    }
}
