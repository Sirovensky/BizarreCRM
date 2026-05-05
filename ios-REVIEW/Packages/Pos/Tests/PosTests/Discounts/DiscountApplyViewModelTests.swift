#if canImport(UIKit)
import XCTest
@testable import Pos

/// Tests for `DiscountApplyViewModel`.
/// Covers: percent vs flat input parsing, validation, canProceed gate, "Other"
/// reason requires note, requestPinApproval state transition, managerApproved
/// request construction (both percent and flat), clamp-to-subtotal, cancellation.
@MainActor
final class DiscountApplyViewModelTests: XCTestCase {

    private func makeVM() -> DiscountApplyViewModel { DiscountApplyViewModel() }

    // MARK: - Initial state

    func test_initialState_isPendingForm() {
        let vm = makeVM()
        if case .pendingForm = vm.approvalState { XCTAssert(true) }
        else { XCTFail("Expected .pendingForm, got \(vm.approvalState)") }
    }

    func test_initialState_cannotProceed() {
        XCTAssertFalse(makeVM().canProceed)
    }

    // MARK: - Percent input validation

    func test_validPercent_canProceed() {
        let vm = makeVM()
        vm.percentInput = "10"
        XCTAssertTrue(vm.canProceed)
    }

    func test_percentOver100_inputError() {
        let vm = makeVM()
        vm.percentInput = "101"
        XCTAssertNotNil(vm.inputError)
        XCTAssertFalse(vm.canProceed)
    }

    func test_zeroPercent_inputError() {
        let vm = makeVM()
        vm.percentInput = "0"
        XCTAssertNotNil(vm.inputError)
    }

    func test_negativePercent_inputError() {
        let vm = makeVM()
        vm.percentInput = "-5"
        XCTAssertNotNil(vm.inputError)
    }

    func test_nonNumericPercent_inputError() {
        let vm = makeVM()
        vm.percentInput = "abc"
        XCTAssertNotNil(vm.inputError)
    }

    func test_emptyPercent_noError_butCannotProceed() {
        let vm = makeVM()
        vm.percentInput = ""
        XCTAssertNil(vm.inputError)
        XCTAssertFalse(vm.canProceed)
    }

    func test_parsedPercent_roundTrip() {
        let vm = makeVM()
        vm.percentInput = "15"
        XCTAssertEqual(vm.parsedPercent, 0.15, accuracy: 1e-9)
    }

    // MARK: - Flat-cents input validation

    func test_validFlatCents_canProceed() {
        let vm = makeVM()
        vm.usePercent = false
        vm.flatCentsInput = "500"
        XCTAssertTrue(vm.canProceed)
    }

    func test_zeroFlatCents_inputError() {
        let vm = makeVM()
        vm.usePercent = false
        vm.flatCentsInput = "0"
        XCTAssertNotNil(vm.inputError)
    }

    func test_negativeFlatCents_inputError() {
        let vm = makeVM()
        vm.usePercent = false
        vm.flatCentsInput = "-100"
        XCTAssertNotNil(vm.inputError)
    }

    func test_nonNumericFlat_inputError() {
        let vm = makeVM()
        vm.usePercent = false
        vm.flatCentsInput = "five"
        XCTAssertNotNil(vm.inputError)
    }

    func test_parsedFlatCents_roundTrip() {
        let vm = makeVM()
        vm.usePercent = false
        vm.flatCentsInput = "750"
        XCTAssertEqual(vm.parsedFlatCents, 750)
    }

    // MARK: - "Other" reason requires note

    func test_otherReason_emptyNote_cannotProceed() {
        let vm = makeVM()
        vm.percentInput = "10"
        vm.reasonCode = .other
        vm.note = ""
        XCTAssertFalse(vm.canProceed)
    }

    func test_otherReason_whitespaceNote_cannotProceed() {
        let vm = makeVM()
        vm.percentInput = "10"
        vm.reasonCode = .other
        vm.note = "   "
        XCTAssertFalse(vm.canProceed)
    }

    func test_otherReason_nonEmptyNote_canProceed() {
        let vm = makeVM()
        vm.percentInput = "10"
        vm.reasonCode = .other
        vm.note = "Customer had an issue"
        XCTAssertTrue(vm.canProceed)
    }

    func test_nonOtherReason_noNote_canProceed() {
        let vm = makeVM()
        vm.percentInput = "20"
        vm.reasonCode = .priceMatch
        vm.note = ""
        XCTAssertTrue(vm.canProceed)
    }

    // MARK: - requestPinApproval state transition

    func test_requestPinApproval_whenCanProceed_movesToPendingPin() {
        let vm = makeVM()
        vm.percentInput = "10"
        vm.requestPinApproval()
        if case .pendingPin = vm.approvalState { XCTAssert(true) }
        else { XCTFail("Expected .pendingPin, got \(vm.approvalState)") }
    }

    func test_requestPinApproval_whenCannotProceed_staysPendingForm() {
        let vm = makeVM()
        // No input provided → cannotProceed
        vm.requestPinApproval()
        if case .pendingForm = vm.approvalState { XCTAssert(true) }
        else { XCTFail("Expected .pendingForm, got \(vm.approvalState)") }
    }

    // MARK: - managerApproved: percent

    func test_managerApproved_percent_computesDiscountCents() {
        let vm = makeVM()
        vm.percentInput = "10"
        vm.reasonCode = .customerLoyalty
        vm.requestPinApproval()
        vm.managerApproved(managerId: 42, subtotalCents: 10_000)

        guard case .approved(let req) = vm.approvalState else {
            XCTFail("Expected .approved"); return
        }
        XCTAssertEqual(req.discountCents, 1_000)
        XCTAssertTrue(req.isPercent)
        XCTAssertEqual(req.discountPercent, 0.10, accuracy: 1e-9)
        XCTAssertEqual(req.reasonCode, .customerLoyalty)
        XCTAssertEqual(req.managerId, 42)
    }

    func test_managerApproved_flat_producesCorrectRequest() {
        let vm = makeVM()
        vm.usePercent = false
        vm.flatCentsInput = "500"
        vm.reasonCode = .priceMatch
        vm.requestPinApproval()
        vm.managerApproved(managerId: 7, subtotalCents: 5_000)

        guard case .approved(let req) = vm.approvalState else {
            XCTFail("Expected .approved"); return
        }
        XCTAssertEqual(req.discountCents, 500)
        XCTAssertFalse(req.isPercent)
        XCTAssertNil(req.discountPercent)
        XCTAssertEqual(req.reasonCode, .priceMatch)
    }

    // MARK: - Clamp to subtotal

    func test_managerApproved_percent_clampedToSubtotal() {
        let vm = makeVM()
        vm.percentInput = "100"  // 100% off
        vm.requestPinApproval()
        vm.managerApproved(managerId: 1, subtotalCents: 3_000)

        guard case .approved(let req) = vm.approvalState else {
            XCTFail("Expected .approved"); return
        }
        XCTAssertLessThanOrEqual(req.discountCents, 3_000)
        XCTAssertEqual(req.discountCents, 3_000)
    }

    func test_managerApproved_flat_clampedToSubtotal() {
        let vm = makeVM()
        vm.usePercent = false
        vm.flatCentsInput = "99999"   // larger than any realistic cart
        vm.requestPinApproval()
        vm.managerApproved(managerId: 1, subtotalCents: 2_000)

        guard case .approved(let req) = vm.approvalState else {
            XCTFail("Expected .approved"); return
        }
        XCTAssertEqual(req.discountCents, 2_000)
    }

    // MARK: - Note is trimmed

    func test_managerApproved_noteTrimmed() {
        let vm = makeVM()
        vm.percentInput = "5"
        vm.reasonCode = .other
        vm.note = "  some note  "
        vm.requestPinApproval()
        vm.managerApproved(managerId: 1, subtotalCents: 1_000)

        guard case .approved(let req) = vm.approvalState else {
            XCTFail("Expected .approved"); return
        }
        XCTAssertEqual(req.note, "some note")
    }

    // MARK: - Cancellation

    func test_managerCancelled_returnsToPendingForm() {
        let vm = makeVM()
        vm.percentInput = "10"
        vm.requestPinApproval()
        XCTAssertEqual({ if case .pendingPin = vm.approvalState { return true }; return false }(), true)

        vm.managerCancelled()
        if case .pendingForm = vm.approvalState { XCTAssert(true) }
        else { XCTFail("Expected .pendingForm after cancellation") }
    }
}

// MARK: - DiscountReasonCode tests

final class DiscountReasonCodeTests: XCTestCase {

    func test_allCases_haveDisplayName() {
        for code in DiscountReasonCode.allCases {
            XCTAssertFalse(code.displayName.isEmpty,
                           "\(code.rawValue) missing displayName")
        }
    }

    func test_allCases_haveIconName() {
        for code in DiscountReasonCode.allCases {
            XCTAssertFalse(code.iconName.isEmpty,
                           "\(code.rawValue) missing iconName")
        }
    }

    func test_rawValues_areStable() {
        // If these fail after a rename the server payload breaks.
        XCTAssertEqual(DiscountReasonCode.customerLoyalty.rawValue,  "customer_loyalty")
        XCTAssertEqual(DiscountReasonCode.priceMatch.rawValue,        "price_match")
        XCTAssertEqual(DiscountReasonCode.damageOrDefect.rawValue,    "damage_or_defect")
        XCTAssertEqual(DiscountReasonCode.employeeDiscount.rawValue,  "employee_discount")
        XCTAssertEqual(DiscountReasonCode.promotionalEvent.rawValue,  "promotional_event")
        XCTAssertEqual(DiscountReasonCode.managerCourtesy.rawValue,   "manager_courtesy")
        XCTAssertEqual(DiscountReasonCode.other.rawValue,             "other")
    }
}
#endif
