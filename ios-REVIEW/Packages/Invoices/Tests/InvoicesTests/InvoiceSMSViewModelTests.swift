import XCTest
@testable import Invoices
import Networking
import Core

// §7.2 InvoiceSMSViewModel tests

@MainActor
final class InvoiceSMSViewModelTests: XCTestCase {

    private func makeStub(succeed: Bool) -> StubAPIClient {
        let payload = "{\"id\":1,\"direction\":\"outbound\"}".data(using: .utf8)!
        if succeed {
            return StubAPIClient(postResults: ["/sms/send": .success(payload)])
        } else {
            return StubAPIClient(postResults: ["/sms/send": .failure(AppError.server(statusCode: 500, message: "SMS error"))])
        }
    }

    private func makeSut(api: StubAPIClient? = nil,
                         phone: String = "+15550001111",
                         paymentLinkURL: String? = nil) -> InvoiceSMSViewModel {
        InvoiceSMSViewModel(
            api: api ?? makeStub(succeed: true),
            invoiceId: 1,
            orderId: "INV-0042",
            customerPhone: phone.isEmpty ? nil : phone,
            paymentLinkURL: paymentLinkURL
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

    func test_prefillsCustomerPhone() {
        let vm = makeSut(phone: "+15550009999")
        XCTAssertEqual(vm.phone, "+15550009999")
    }

    func test_messageContainsOrderId() {
        let vm = makeSut()
        XCTAssertTrue(vm.messageBody.contains("INV-0042"))
    }

    func test_messageContainsPaymentLinkURL() {
        let vm = makeSut(paymentLinkURL: "https://pay.example.com/abc")
        XCTAssertTrue(vm.messageBody.contains("https://pay.example.com/abc"))
    }

    // MARK: - isValid

    func test_isValid_trueWhenPhoneAndMessagePresent() {
        let vm = makeSut()
        XCTAssertTrue(vm.isValid)
    }

    func test_isValid_falseWhenPhoneEmpty() {
        let vm = makeSut()
        vm.phone = ""
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_falseWhenMessageEmpty() {
        let vm = makeSut()
        vm.messageBody = ""
        XCTAssertFalse(vm.isValid)
    }

    // MARK: - send

    func test_send_happyPath_transitionsToSuccess() async {
        let vm = makeSut(api: makeStub(succeed: true))
        await vm.send()
        guard case .success = vm.state else {
            XCTFail("Expected .success, got \(vm.state)")
            return
        }
    }

    func test_send_invalidInput_setsFailed() async {
        let vm = makeSut()
        vm.phone = ""
        await vm.send()
        guard case .failed = vm.state else {
            XCTFail("Expected .failed for empty phone")
            return
        }
    }

    func test_send_serverError_setsFailed() async {
        let vm = makeSut(api: makeStub(succeed: false))
        await vm.send()
        guard case .failed = vm.state else {
            XCTFail("Expected .failed on server error")
            return
        }
    }

    // MARK: - resetToIdle

    func test_resetToIdle_fromFailed_becomesIdle() async {
        let vm = makeSut(api: makeStub(succeed: false))
        await vm.send()
        vm.resetToIdle()
        guard case .idle = vm.state else {
            XCTFail("Expected .idle after reset")
            return
        }
    }
}
