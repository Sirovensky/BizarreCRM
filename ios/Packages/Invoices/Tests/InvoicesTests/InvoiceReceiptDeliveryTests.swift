import XCTest
@testable import Invoices

// §7.4 InvoiceReceiptDeliveryViewModel tests — agent-6 b8

final class InvoiceReceiptDeliveryTests: XCTestCase {

    // MARK: - Helpers

    private func makeVM(
        emailResult: Result<Void, Error> = .success(()),
        smsResult: Result<Void, Error> = .success(()),
        paymentCents: Int = 5000
    ) -> (InvoiceReceiptDeliveryViewModel, StubReceiptDeliveryRepository) {
        let repo = StubReceiptDeliveryRepository(emailResult: emailResult, smsResult: smsResult)
        let vm = InvoiceReceiptDeliveryViewModel(
            invoiceId: 42,
            invoiceNumber: "INV-0042",
            customerEmail: "customer@example.com",
            customerPhone: "+15550001234",
            paymentCents: paymentCents,
            repository: repo
        )
        return (vm, repo)
    }

    // MARK: - Init

    @MainActor
    func test_init_prefillsEmailAndPhone() async {
        let (vm, _) = makeVM()
        XCTAssertEqual(vm.emailAddress, "customer@example.com")
        XCTAssertEqual(vm.phone, "+15550001234")
        XCTAssertEqual(vm.invoiceId, 42)
        XCTAssertEqual(vm.invoiceNumber, "INV-0042")
        XCTAssertEqual(vm.paymentCents, 5000)
        XCTAssertEqual(vm.state, .idle)
    }

    // MARK: - sendEmail success

    @MainActor
    func test_sendEmail_success_setsSuccessState() async {
        let (vm, repo) = makeVM(emailResult: .success(()))
        vm.emailAddress = "test@example.com"
        await vm.sendEmail()
        XCTAssertEqual(repo.emailCallCount, 1)
        XCTAssertEqual(repo.lastEmail, "test@example.com")
        if case let .success(msg) = vm.state {
            XCTAssertTrue(msg.contains("test@example.com"))
        } else {
            XCTFail("Expected .success state, got \(vm.state)")
        }
    }

    @MainActor
    func test_sendEmail_emptyEmail_returnsFailed() async {
        let (vm, repo) = makeVM()
        vm.emailAddress = "  "
        await vm.sendEmail()
        XCTAssertEqual(repo.emailCallCount, 0)
        if case .failed = vm.state { /* pass */ } else {
            XCTFail("Expected .failed state")
        }
    }

    @MainActor
    func test_sendEmail_networkError_setsFailedState() async {
        let (vm, _) = makeVM(emailResult: .failure(URLError(.notConnectedToInternet)))
        vm.emailAddress = "x@y.com"
        await vm.sendEmail()
        if case let .failed(msg) = vm.state {
            XCTAssertFalse(msg.isEmpty)
        } else {
            XCTFail("Expected .failed state")
        }
    }

    // MARK: - sendSMS success

    @MainActor
    func test_sendSMS_success_setsSuccessState() async {
        let (vm, repo) = makeVM(smsResult: .success(()))
        vm.phone = "+15550001234"
        await vm.sendSMS()
        XCTAssertEqual(repo.smsCallCount, 1)
        XCTAssertEqual(repo.lastPhone, "+15550001234")
        if case let .success(msg) = vm.state {
            XCTAssertTrue(msg.contains("+15550001234"))
        } else {
            XCTFail("Expected .success state, got \(vm.state)")
        }
    }

    @MainActor
    func test_sendSMS_emptyPhone_returnsFailed() async {
        let (vm, repo) = makeVM()
        vm.phone = ""
        await vm.sendSMS()
        XCTAssertEqual(repo.smsCallCount, 0)
        if case .failed = vm.state { /* pass */ } else {
            XCTFail("Expected .failed state")
        }
    }

    @MainActor
    func test_sendSMS_messageContainsInvoiceNumberAndTotal() async {
        let (vm, repo) = makeVM(smsResult: .success(()))
        vm.phone = "+1"
        await vm.sendSMS()
        XCTAssertTrue(repo.lastMessage?.contains("INV-0042") ?? false)
        XCTAssertTrue(repo.lastMessage?.contains("$50.00") ?? false || repo.lastMessage?.contains("50") ?? false)
    }

    // MARK: - resetToIdle

    @MainActor
    func test_resetToIdle_clearsState() async {
        let (vm, _) = makeVM(emailResult: .failure(URLError(.cannotConnectToHost)))
        vm.emailAddress = "a@b.com"
        await vm.sendEmail()
        if case .failed = vm.state { /* pass */ } else {
            XCTFail("Expected failed state first")
        }
        vm.resetToIdle()
        XCTAssertEqual(vm.state, .idle)
    }
}

// MARK: - Stub

final class StubReceiptDeliveryRepository: InvoiceReceiptDeliveryRepository, @unchecked Sendable {
    private(set) var emailCallCount = 0
    private(set) var lastEmail: String?
    private(set) var smsCallCount = 0
    private(set) var lastPhone: String?
    private(set) var lastMessage: String?

    private let emailResult: Result<Void, Error>
    private let smsResult: Result<Void, Error>

    init(emailResult: Result<Void, Error>, smsResult: Result<Void, Error>) {
        self.emailResult = emailResult
        self.smsResult = smsResult
    }

    func emailReceipt(invoiceId: Int64, email: String) async throws {
        emailCallCount += 1
        lastEmail = email
        try emailResult.get()
    }

    func smsReceipt(phone: String, message: String) async throws {
        smsCallCount += 1
        lastPhone = phone
        lastMessage = message
        try smsResult.get()
    }
}
