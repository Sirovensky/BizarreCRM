import XCTest
@testable import Invoices
import Networking

// §7.2 InvoiceCreditNoteViewModel tests

@MainActor
final class InvoiceCreditNoteViewModelTests: XCTestCase {

    private func makeVM(api: StubAPIClient, invoiceId: Int64 = 1, maxCents: Int = 5000) -> InvoiceCreditNoteViewModel {
        InvoiceCreditNoteViewModel(api: api, invoiceId: invoiceId, maxCents: maxCents)
    }

    // MARK: - Initial state

    func test_initialState_isIdle() {
        let vm = makeVM(api: StubAPIClient())
        guard case .idle = vm.state else {
            XCTFail("Expected .idle")
            return
        }
    }

    func test_initialAmountCents_equalsMaxCents() {
        let vm = makeVM(api: StubAPIClient(), maxCents: 3000)
        XCTAssertEqual(vm.amountCents, 3000)
    }

    func test_initialAmountString_formattedCorrectly() {
        let vm = makeVM(api: StubAPIClient(), maxCents: 3000)
        XCTAssertEqual(vm.amountString, "30.00")
    }

    // MARK: - isValid

    func test_isValid_falseWithEmptyReason() {
        let vm = makeVM(api: StubAPIClient())
        vm.reason = ""
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_falseWhenAmountZero() {
        let vm = makeVM(api: StubAPIClient())
        vm.reason = "overpayment"
        vm.amountCents = 0
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_falseWhenAmountExceedsMax() {
        let vm = makeVM(api: StubAPIClient(), maxCents: 5000)
        vm.reason = "overpayment"
        vm.amountCents = 6000
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_trueWhenAllFieldsSet() {
        let vm = makeVM(api: StubAPIClient(), maxCents: 5000)
        vm.reason = "overpayment"
        vm.amountCents = 3000
        XCTAssertTrue(vm.isValid)
    }

    // MARK: - updateAmount

    func test_updateAmount_setsAmountCents() {
        let vm = makeVM(api: StubAPIClient())
        vm.updateAmount(from: "25.00")
        XCTAssertEqual(vm.amountCents, 2500)
    }

    func test_updateAmount_ignoresNonNumeric() {
        let vm = makeVM(api: StubAPIClient(), maxCents: 5000)
        vm.updateAmount(from: "abc")
        // Should not crash; amountCents stays at default
        XCTAssertEqual(vm.amountCents, 5000)
    }

    // MARK: - submit success

    func test_submit_success_stateIsSuccess() async {
        let payload = """
        {"id": 42, "reference_number": "CN-0042"}
        """.data(using: .utf8)!
        let api = StubAPIClient(postResults: ["/credit-note": .success(payload)])
        let vm = makeVM(api: api, maxCents: 5000)
        vm.reason = "Overpayment refund"
        vm.amountCents = 5000
        await vm.submit()
        if case .success(let ref) = vm.state {
            XCTAssertEqual(ref, "CN-0042")
        } else {
            XCTFail("Expected .success, got \(vm.state)")
        }
    }

    // MARK: - submit failure

    func test_submit_failure_stateIsFailed() async {
        struct FakeError: Error, LocalizedError {
            var errorDescription: String? { "Network error" }
        }
        let api = StubAPIClient(postResults: ["/credit-note": .failure(FakeError())])
        let vm = makeVM(api: api, maxCents: 5000)
        vm.reason = "Overpayment refund"
        vm.amountCents = 5000
        await vm.submit()
        if case .failed(let msg) = vm.state {
            XCTAssertFalse(msg.isEmpty)
        } else {
            XCTFail("Expected .failed, got \(vm.state)")
        }
    }

    // MARK: - reset

    func test_reset_fromFailed_returnsIdle() async {
        struct FakeError: Error {}
        let api = StubAPIClient(postResults: ["/credit-note": .failure(FakeError())])
        let vm = makeVM(api: api, maxCents: 5000)
        vm.reason = "test"
        vm.amountCents = 1000
        await vm.submit()
        vm.reset()
        guard case .idle = vm.state else {
            XCTFail("Expected .idle after reset")
            return
        }
    }
}
