import XCTest
@testable import Invoices
import Networking
import Core

// §7.7 InvoiceReturnViewModel + RestockingFeePolicy tests
// Covers: line selection, restocking fee calc, fraud threshold, manager PIN gate,
//         tender selection, disposition, submit states, error mapping.

@MainActor
final class InvoiceReturnViewModelTests: XCTestCase {

    // MARK: - Fixtures

    private func makeLine(
        id: Int64 = 1,
        displayName: String = "iPhone Screen",
        originalQty: Int = 2,
        unitPriceCents: Int = 5000
    ) -> InvoiceReturnLine {
        InvoiceReturnLine(
            id: id,
            displayName: displayName,
            originalQty: originalQty,
            unitPriceCents: unitPriceCents
        )
    }

    private func makeSut(
        api: StubAPIClient = StubAPIClient(),
        lines: [InvoiceReturnLine] = [],
        policy: RestockingFeePolicy? = nil,
        daysSincePurchase: Int = 0
    ) -> InvoiceReturnViewModel {
        InvoiceReturnViewModel(
            api: api,
            invoiceId: 42,
            customerId: 7,
            lines: lines,
            restockingFeePolicy: policy,
            daysSincePurchase: daysSincePurchase
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

    func test_initialTender_isCash() {
        XCTAssertEqual(makeSut().selectedTender, .cash)
    }

    func test_initialReason_isEmpty() {
        XCTAssertTrue(makeSut().returnReason.isEmpty)
    }

    // MARK: - selectedLines

    func test_selectedLines_emptyWhenNoneSelected() {
        let vm = makeSut(lines: [makeLine(), makeLine(id: 2)])
        XCTAssertTrue(vm.selectedLines.isEmpty)
    }

    func test_selectedLines_filtersToSelected() {
        var line1 = makeLine(id: 1)
        var line2 = makeLine(id: 2)
        line1.isSelected = true
        let vm = makeSut(lines: [line1, line2])
        XCTAssertEqual(vm.selectedLines.count, 1)
        XCTAssertEqual(vm.selectedLines.first?.id, 1)
    }

    // MARK: - grossRefundCents

    func test_grossRefundCents_sumOfSelectedLines() {
        var line1 = makeLine(id: 1, unitPriceCents: 3000)  // qty default = 2 → 6000
        var line2 = makeLine(id: 2, unitPriceCents: 1000)  // qty = 2 → 2000
        line1.isSelected = true
        line2.isSelected = true
        let vm = makeSut(lines: [line1, line2])
        XCTAssertEqual(vm.grossRefundCents, 8000)
    }

    func test_grossRefundCents_zeroWhenNoneSelected() {
        let vm = makeSut(lines: [makeLine()])
        XCTAssertEqual(vm.grossRefundCents, 0)
    }

    // MARK: - RestockingFeePolicy tests

    func test_noPolicy_feesAreZero() {
        var line = makeLine(unitPriceCents: 5000)
        line.isSelected = true
        let vm = makeSut(lines: [line], policy: nil)
        XCTAssertEqual(vm.totalRestockingFeeCents, 0)
        XCTAssertEqual(vm.netRefundCents, vm.grossRefundCents)
    }

    func test_flatFeePolicy_deductedFromGross() {
        var line = makeLine(id: 1, originalQty: 1, unitPriceCents: 10_000)
        line.isSelected = true
        let policy = RestockingFeePolicy(flatFeeCentsPerUnit: 500)
        let vm = makeSut(lines: [line], policy: policy)
        // gross = 10000, flat = 500×1 = 500, net = 9500
        XCTAssertEqual(vm.totalRestockingFeeCents, 500)
        XCTAssertEqual(vm.netRefundCents, 9_500)
    }

    func test_percentPolicy_deductedFromGross() {
        var line = makeLine(id: 1, originalQty: 1, unitPriceCents: 10_000)
        line.isSelected = true
        let policy = RestockingFeePolicy(percentOfLine: 0.15) // 15%
        let vm = makeSut(lines: [line], policy: policy)
        // gross = 10000, fee = 1500, net = 8500
        XCTAssertEqual(vm.totalRestockingFeeCents, 1_500)
        XCTAssertEqual(vm.netRefundCents, 8_500)
    }

    func test_noFeeWindowPolicy_noFeeWithinWindow() {
        var line = makeLine(id: 1, originalQty: 1, unitPriceCents: 5_000)
        line.isSelected = true
        let policy = RestockingFeePolicy(flatFeeCentsPerUnit: 500, noFeeWindowDays: 30)
        let vm = makeSut(lines: [line], policy: policy, daysSincePurchase: 10)
        // within window → no fee
        XCTAssertEqual(vm.totalRestockingFeeCents, 0)
        XCTAssertEqual(vm.netRefundCents, 5_000)
    }

    func test_noFeeWindowPolicy_feeAppliedBeyondWindow() {
        var line = makeLine(id: 1, originalQty: 1, unitPriceCents: 5_000)
        line.isSelected = true
        let policy = RestockingFeePolicy(flatFeeCentsPerUnit: 500, noFeeWindowDays: 30)
        let vm = makeSut(lines: [line], policy: policy, daysSincePurchase: 31)
        XCTAssertEqual(vm.totalRestockingFeeCents, 500)
    }

    func test_netRefundCents_neverNegative() {
        var line = makeLine(id: 1, originalQty: 1, unitPriceCents: 100)
        line.isSelected = true
        // Fee exceeds gross
        let policy = RestockingFeePolicy(flatFeeCentsPerUnit: 1_000)
        let vm = makeSut(lines: [line], policy: policy)
        XCTAssertGreaterThanOrEqual(vm.netRefundCents, 0)
    }

    // MARK: - Fraud threshold

    func test_exceedsFraudThreshold_falseBelow20000() {
        var line = makeLine(id: 1, originalQty: 1, unitPriceCents: 19_999)
        line.isSelected = true
        let vm = makeSut(lines: [line])
        XCTAssertFalse(vm.exceedsFraudThreshold)
    }

    func test_exceedsFraudThreshold_trueAbove20000() {
        var line = makeLine(id: 1, originalQty: 1, unitPriceCents: 20_001)
        line.isSelected = true
        let vm = makeSut(lines: [line])
        XCTAssertTrue(vm.exceedsFraudThreshold)
    }

    func test_requiresManagerPin_matchesFraudThreshold() {
        let vm = makeSut()
        // No lines selected → 0 → false
        XCTAssertFalse(vm.requiresManagerPin)
    }

    // MARK: - isValid

    func test_isValid_falseWhenNoLinesSelected() {
        let vm = makeSut(lines: [makeLine()])
        vm.returnReason = "Broken"
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_falseWhenReasonEmpty() {
        var line = makeLine()
        line.isSelected = true
        let vm = makeSut(lines: [line])
        vm.returnReason = ""
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_trueWhenLineSelectedAndReasonPresent() {
        var line = makeLine()
        line.isSelected = true
        let vm = makeSut(lines: [line])
        vm.returnReason = "Customer returned"
        XCTAssertTrue(vm.isValid)
    }

    // MARK: - Submit

    func test_submitReturn_invalidForm_setsFailed() async {
        let vm = makeSut(lines: [makeLine()]) // no lines selected
        vm.returnReason = "Test"
        await vm.submitReturn()
        guard case .failed = vm.state else {
            XCTFail("Expected .failed for invalid form")
            return
        }
    }

    func test_submitReturn_highAmount_showsFraudWarning() async {
        var line = makeLine(id: 1, originalQty: 1, unitPriceCents: 30_000)
        line.isSelected = true
        let vm = makeSut(api: .returnSuccess(id: 55), lines: [line])
        vm.returnReason = "Customer changed mind"
        await vm.submitReturn()
        XCTAssertTrue(vm.showFraudWarning)
        guard case .idle = vm.state else {
            XCTFail("Expected .idle while awaiting fraud acknowledgment")
            return
        }
    }

    func test_acknowledgeFraudWarning_opensManagerPinPrompt() async {
        var line = makeLine(id: 1, originalQty: 1, unitPriceCents: 30_000)
        line.isSelected = true
        let vm = makeSut(api: .returnSuccess(id: 55), lines: [line])
        vm.returnReason = "Customer changed mind"
        await vm.submitReturn()
        vm.acknowledgeFraudWarning()
        XCTAssertFalse(vm.showFraudWarning)
        XCTAssertTrue(vm.showManagerPinPrompt)
    }

    func test_submitWithPin_succeeds() async {
        var line = makeLine(id: 1, originalQty: 1, unitPriceCents: 30_000)
        line.isSelected = true
        let vm = makeSut(api: .returnSuccess(id: 77), lines: [line])
        vm.returnReason = "Customer returned"
        await vm.submitWithPin("9876")
        guard case .success(let refundId) = vm.state else {
            XCTFail("Expected .success after PIN")
            return
        }
        XCTAssertEqual(refundId, 77)
    }

    func test_submitReturn_success_onSmallAmount() async {
        var line = makeLine(id: 1, originalQty: 1, unitPriceCents: 1_000)
        line.isSelected = true
        let vm = makeSut(api: .returnSuccess(id: 99), lines: [line])
        vm.returnReason = "Defective"
        await vm.submitReturn()
        guard case .success(let refundId) = vm.state else {
            XCTFail("Expected .success")
            return
        }
        XCTAssertEqual(refundId, 99)
    }

    // MARK: - Tender selection

    func test_tenderSelection_storeCredit() {
        let vm = makeSut()
        vm.selectedTender = .storeCredit
        XCTAssertEqual(vm.selectedTender, .storeCredit)
    }

    func test_tenderSelection_giftCard() {
        let vm = makeSut()
        vm.selectedTender = .giftCard
        XCTAssertEqual(vm.selectedTender, .giftCard)
    }

    // MARK: - Disposition

    func test_disposition_defaultSalable() {
        let line = makeLine()
        XCTAssertEqual(line.disposition, .salable)
    }

    func test_allDispositions_haveDisplayNames() {
        for d in RestockDisposition.allCases {
            XCTAssertFalse(d.displayName.isEmpty)
        }
    }

    func test_allDispositions_haveSystemImages() {
        for d in RestockDisposition.allCases {
            XCTAssertFalse(d.systemImage.isEmpty)
        }
    }

    // MARK: - ReturnTender enum

    func test_allReturnTenders_haveDisplayNames() {
        for t in ReturnTender.allCases {
            XCTAssertFalse(t.displayName.isEmpty)
        }
    }

    func test_allReturnTenders_haveSystemImages() {
        for t in ReturnTender.allCases {
            XCTAssertFalse(t.systemImage.isEmpty)
        }
    }

    // MARK: - resetToIdle

    func test_resetToIdle_fromFailed_becomesIdle() async {
        let vm = makeSut()
        // Trigger failed by submitting invalid form
        await vm.submitReturn()
        vm.resetToIdle()
        guard case .idle = vm.state else {
            XCTFail("Expected .idle after reset")
            return
        }
    }
}

// MARK: - RestockingFeePolicy unit tests

final class RestockingFeePolicyTests: XCTestCase {

    func test_flatFeeOnlyPolicy_computesFee() {
        let policy = RestockingFeePolicy(flatFeeCentsPerUnit: 200)
        let fee = policy.fee(grossCents: 5_000, qtyReturned: 3)
        XCTAssertEqual(fee, 600)
    }

    func test_percentOnlyPolicy_computesFee() {
        let policy = RestockingFeePolicy(percentOfLine: 0.10)
        let fee = policy.fee(grossCents: 10_000, qtyReturned: 1)
        XCTAssertEqual(fee, 1_000)
    }

    func test_combinedPolicy_sumsFlatAndPercent() {
        let policy = RestockingFeePolicy(flatFeeCentsPerUnit: 100, percentOfLine: 0.05)
        // flat=100×2=200, pct=5%×4000=200, total=400
        let fee = policy.fee(grossCents: 4_000, qtyReturned: 2)
        XCTAssertEqual(fee, 400)
    }

    func test_feeCannotExceedGross() {
        let policy = RestockingFeePolicy(flatFeeCentsPerUnit: 10_000)
        let fee = policy.fee(grossCents: 500, qtyReturned: 1)
        XCTAssertLessThanOrEqual(fee, 500)
    }

    func test_classFilter_matchingClassApplieFee() {
        let policy = RestockingFeePolicy(flatFeeCentsPerUnit: 300, itemClasses: ["electronics"])
        let fee = policy.fee(grossCents: 5_000, qtyReturned: 1, itemClass: "electronics")
        XCTAssertEqual(fee, 300)
    }

    func test_classFilter_nonMatchingClassNoFee() {
        let policy = RestockingFeePolicy(flatFeeCentsPerUnit: 300, itemClasses: ["electronics"])
        let fee = policy.fee(grossCents: 5_000, qtyReturned: 1, itemClass: "accessories")
        XCTAssertEqual(fee, 0)
    }

    func test_noFeeWindowDays_withinWindow_noFee() {
        let policy = RestockingFeePolicy(flatFeeCentsPerUnit: 500, noFeeWindowDays: 14)
        let fee = policy.fee(grossCents: 5_000, qtyReturned: 1, daysSincePurchase: 7)
        XCTAssertEqual(fee, 0)
    }

    func test_noFeeWindowDays_atBoundary_noFee() {
        let policy = RestockingFeePolicy(flatFeeCentsPerUnit: 500, noFeeWindowDays: 14)
        let fee = policy.fee(grossCents: 5_000, qtyReturned: 1, daysSincePurchase: 14)
        XCTAssertEqual(fee, 0)
    }

    func test_noFeeWindowDays_beyondWindow_feeApplied() {
        let policy = RestockingFeePolicy(flatFeeCentsPerUnit: 500, noFeeWindowDays: 14)
        let fee = policy.fee(grossCents: 5_000, qtyReturned: 1, daysSincePurchase: 15)
        XCTAssertEqual(fee, 500)
    }

    func test_noPolicy_zeroFee() {
        let policy = RestockingFeePolicy()
        let fee = policy.fee(grossCents: 10_000, qtyReturned: 2)
        XCTAssertEqual(fee, 0)
    }
}

// MARK: - StubAPIClient return extension

extension StubAPIClient {
    static func returnSuccess(id: Int64 = 1) -> StubAPIClient {
        let payload = """
        {"id":\(id)}
        """.data(using: .utf8)!
        return StubAPIClient(postResults: ["/refunds": .success(payload)])
    }

    static func returnFailure(_ error: Error) -> StubAPIClient {
        StubAPIClient(postResults: ["/refunds": .failure(error)])
    }
}
