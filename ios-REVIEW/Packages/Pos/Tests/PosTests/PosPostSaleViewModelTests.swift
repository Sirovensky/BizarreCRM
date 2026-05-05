import XCTest
@testable import Pos

/// §16.7 — `PosPostSaleViewModel` tests. Platform-agnostic; no UIKit
/// imports so the suite can run in the Swift package context without a
/// simulator host.
@MainActor
final class PosPostSaleViewModelTests: XCTestCase {

    // MARK: - Email validation

    func test_isValidEmail_acceptsBasicAddress() {
        XCTAssertTrue(PosPostSaleViewModel.isValidEmail("ada@example.com"))
    }

    func test_isValidEmail_rejectsMissingAt() {
        XCTAssertFalse(PosPostSaleViewModel.isValidEmail("no-at-sign.com"))
    }

    func test_isValidEmail_rejectsMissingDot() {
        XCTAssertFalse(PosPostSaleViewModel.isValidEmail("ada@localhost"))
    }

    func test_isValidEmail_rejectsTrailingDot() {
        XCTAssertFalse(PosPostSaleViewModel.isValidEmail("ada@example."))
    }

    func test_isValidEmail_rejectsWhitespace() {
        XCTAssertFalse(PosPostSaleViewModel.isValidEmail("ada @example.com"))
    }

    func test_isValidEmail_rejectsSingleChar() {
        XCTAssertFalse(PosPostSaleViewModel.isValidEmail("a"))
        XCTAssertFalse(PosPostSaleViewModel.isValidEmail(""))
    }

    func test_isValidEmail_trimsOuterWhitespace() {
        XCTAssertTrue(PosPostSaleViewModel.isValidEmail("  ada@example.com  "))
    }

    // MARK: - Phone validation

    func test_isValidPhone_acceptsFormattedUSNumber() {
        XCTAssertTrue(PosPostSaleViewModel.isValidPhone("(555) 867-5309"))
    }

    func test_isValidPhone_acceptsInternationalPrefix() {
        XCTAssertTrue(PosPostSaleViewModel.isValidPhone("+1-415-555-1212"))
    }

    func test_isValidPhone_rejectsFewDigits() {
        // Six-digit inputs must fail the 7+ threshold.
        XCTAssertFalse(PosPostSaleViewModel.isValidPhone("55-5309"))
        XCTAssertFalse(PosPostSaleViewModel.isValidPhone("123456"))
    }

    func test_isValidPhone_rejectsAllLetters() {
        XCTAssertFalse(PosPostSaleViewModel.isValidPhone("call me"))
    }

    // MARK: - Instance state

    func test_init_seedsEmailAndPhoneFromDefaults() {
        let vm = PosPostSaleViewModel(
            totalCents: 1000,
            methodLabel: "test",
            receiptText: "",
            receiptHtml: "",
            defaultEmail: "hi@example.com",
            defaultPhone: "555-867-5309"
        )
        XCTAssertEqual(vm.emailInput, "hi@example.com")
        XCTAssertEqual(vm.phoneInput, "555-867-5309")
        XCTAssertTrue(vm.isEmailValid)
        XCTAssertTrue(vm.isPhoneValid)
    }

    func test_init_emptyDefaults_isInvalid() {
        let vm = PosPostSaleViewModel(
            totalCents: 1000,
            methodLabel: "test",
            receiptText: "",
            receiptHtml: ""
        )
        XCTAssertFalse(vm.isEmailValid)
        XCTAssertFalse(vm.isPhoneValid)
    }

    // MARK: - Spinner transition

    func test_runSpinner_transitionsToCompleted() async {
        let vm = PosPostSaleViewModel(
            totalCents: 1000,
            methodLabel: "test",
            receiptText: "",
            receiptHtml: "",
            spinnerMillis: 5
        )
        XCTAssertEqual(vm.phase, .processing)
        await vm.runSpinner()
        XCTAssertEqual(vm.phase, .completed)
    }

    // MARK: - Submit flows without API

    func test_submitEmail_withNoApi_surfacesPlaceholderBanner() async {
        let vm = PosPostSaleViewModel(
            totalCents: 500,
            methodLabel: "test",
            receiptText: "",
            receiptHtml: "",
            defaultEmail: "ada@example.com"
        )
        await vm.submitEmail()
        if case .sent(let msg) = vm.emailStatus {
            XCTAssertTrue(msg.contains("placeholder"), "Expected placeholder banner, got \(msg)")
        } else {
            XCTFail("Expected .sent, got \(vm.emailStatus)")
        }
    }

    func test_submitEmail_invalidAddress_fails() async {
        let vm = PosPostSaleViewModel(
            totalCents: 500,
            methodLabel: "test",
            receiptText: "",
            receiptHtml: "",
            defaultEmail: "not-an-email"
        )
        await vm.submitEmail()
        guard case .failed = vm.emailStatus else {
            XCTFail("Expected .failed, got \(vm.emailStatus)")
            return
        }
    }

    func test_submitSms_invalidPhone_fails() async {
        let vm = PosPostSaleViewModel(
            totalCents: 500,
            methodLabel: "test",
            receiptText: "",
            receiptHtml: "",
            defaultPhone: "x"
        )
        await vm.submitSms()
        guard case .failed = vm.smsStatus else {
            XCTFail("Expected .failed, got \(vm.smsStatus)")
            return
        }
    }

    // MARK: - Next sale

    func test_triggerNextSale_firesClosure_andFlagsCartCleared() {
        var cleared = false
        let vm = PosPostSaleViewModel(
            totalCents: 0,
            methodLabel: "test",
            receiptText: "",
            receiptHtml: "",
            nextSale: { cleared = true }
        )
        XCTAssertFalse(vm.cartCleared)
        vm.triggerNextSale()
        XCTAssertTrue(cleared, "nextSale closure must fire")
        XCTAssertTrue(vm.cartCleared)
    }

    // MARK: - Sheet state

    func test_openEmailSheet_resetsStatus_andSetsSheet() {
        let vm = PosPostSaleViewModel(
            totalCents: 0, methodLabel: "", receiptText: "", receiptHtml: ""
        )
        vm.openEmailSheet()
        XCTAssertEqual(vm.activeSheet, .email)
        XCTAssertEqual(vm.emailStatus, .idle)
    }

    func test_dismissSheet_clearsActiveSheet() {
        let vm = PosPostSaleViewModel(
            totalCents: 0, methodLabel: "", receiptText: "", receiptHtml: ""
        )
        vm.openSmsSheet()
        XCTAssertEqual(vm.activeSheet, .sms)
        vm.dismissSheet()
        XCTAssertNil(vm.activeSheet)
    }
}
