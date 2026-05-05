import XCTest
@testable import Invoices
import Networking
import Core

// §7.6 InvoiceEmailReceiptViewModel tests

@MainActor
final class InvoiceEmailReceiptViewModelTests: XCTestCase {

    private func makeStubForReceipt(succeed: Bool) -> StubAPIClient {
        let payload = "{\"success\":true}".data(using: .utf8)!
        if succeed {
            return StubAPIClient(postResults: [
                "/email-receipt": .success(payload),
                "/sms-receipt":   .success(payload)
            ])
        } else {
            return StubAPIClient(postResults: [
                "/email-receipt": .failure(AppError.server(statusCode: 500, message: "Internal error"))
            ])
        }
    }

    private func makeSut(api: StubAPIClient? = nil, email: String = "") -> InvoiceEmailReceiptViewModel {
        InvoiceEmailReceiptViewModel(
            api: api ?? makeStubForReceipt(succeed: true),
            invoiceId: 1,
            customerEmail: email.isEmpty ? nil : email
        )
    }

    // MARK: - Initial state

    func test_initialState_isIdle() {
        let vm = makeSut()
        guard case .idle = vm.state else {
            XCTFail("Expected .idle")
            return
        }
    }

    func test_prefillsCustomerEmail() {
        let vm = makeSut(email: "test@example.com")
        XCTAssertEqual(vm.emailAddress, "test@example.com")
    }

    // MARK: - isValid

    func test_isValid_trueForValidEmail() {
        let vm = makeSut()
        vm.emailAddress = "user@test.com"
        XCTAssertTrue(vm.isValid)
    }

    func test_isValid_falseForEmptyEmail() {
        let vm = makeSut()
        vm.emailAddress = ""
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_falseForEmailWithoutAt() {
        let vm = makeSut()
        vm.emailAddress = "notanemail"
        XCTAssertFalse(vm.isValid)
    }

    // MARK: - send success

    func test_send_happyPath_transitionsToSuccess() async {
        let vm = makeSut(api: makeStubForReceipt(succeed: true), email: "a@b.com")
        await vm.send()
        guard case .success = vm.state else {
            XCTFail("Expected .success, got \(vm.state)")
            return
        }
    }

    func test_send_invalidEmail_setsFailed() async {
        let vm = makeSut()
        vm.emailAddress = ""
        await vm.send()
        guard case .failed = vm.state else {
            XCTFail("Expected .failed for invalid email")
            return
        }
    }

    func test_send_serverError_setsFailed() async {
        let vm = makeSut(api: makeStubForReceipt(succeed: false), email: "a@b.com")
        await vm.send()
        guard case .failed = vm.state else {
            XCTFail("Expected .failed on server error")
            return
        }
    }

    // MARK: - resetToIdle

    func test_resetToIdle_fromFailed_becomesIdle() async {
        let vm = makeSut(api: makeStubForReceipt(succeed: false), email: "a@b.com")
        await vm.send()
        vm.resetToIdle()
        guard case .idle = vm.state else {
            XCTFail("Expected .idle after reset")
            return
        }
    }
}
