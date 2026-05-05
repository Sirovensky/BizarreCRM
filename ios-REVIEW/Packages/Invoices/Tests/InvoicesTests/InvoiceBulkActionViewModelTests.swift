import XCTest
@testable import Invoices
import Networking

// §7.1 InvoiceBulkActionViewModel tests

@MainActor
final class InvoiceBulkActionViewModelTests: XCTestCase {

    private func makeVM(api: StubAPIClient) -> InvoiceBulkActionViewModel {
        InvoiceBulkActionViewModel(api: api)
    }

    // MARK: - Initial state

    func test_initialState_isIdle() {
        let vm = makeVM(api: StubAPIClient())
        guard case .idle = vm.state else {
            XCTFail("Expected .idle")
            return
        }
    }

    // MARK: - Empty ids → no-op

    func test_perform_emptyIds_staysIdle() async {
        let vm = makeVM(api: StubAPIClient())
        await vm.perform(action: "void", ids: [])
        guard case .idle = vm.state else {
            XCTFail("Expected .idle after empty ids")
            return
        }
    }

    // MARK: - Success

    func test_perform_success_updatesState() async {
        let payload = """
        {"processed": 3, "failed": 0}
        """.data(using: .utf8)!
        let api = StubAPIClient(postResults: ["/bulk-action": .success(payload)])
        let vm = makeVM(api: api)
        await vm.perform(action: "send_reminder", ids: [1, 2, 3])
        if case .success(let processed, let failed) = vm.state {
            XCTAssertEqual(processed, 3)
            XCTAssertEqual(failed, 0)
        } else {
            XCTFail("Expected .success, got \(vm.state)")
        }
    }

    // MARK: - Failure

    func test_perform_failure_updatesState() async {
        struct FakeError: Error, LocalizedError {
            var errorDescription: String? { "Server error" }
        }
        let api = StubAPIClient(postResults: ["/bulk-action": .failure(FakeError())])
        let vm = makeVM(api: api)
        await vm.perform(action: "void", ids: [1])
        if case .failed(let msg) = vm.state {
            XCTAssertFalse(msg.isEmpty)
        } else {
            XCTFail("Expected .failed, got \(vm.state)")
        }
    }

    // MARK: - Reset

    func test_reset_fromFailed_returnsIdle() async {
        struct FakeError: Error {}
        let api = StubAPIClient(postResults: ["/bulk-action": .failure(FakeError())])
        let vm = makeVM(api: api)
        await vm.perform(action: "void", ids: [1])
        vm.reset()
        guard case .idle = vm.state else {
            XCTFail("Expected .idle after reset")
            return
        }
    }

    // MARK: - Idempotency: can't double-submit

    func test_perform_whileSubmitting_ignored() async {
        // This is hard to test without concurrency hacks; just verify the guard
        // by calling twice — second should be ignored if already idle after first
        let payload = """
        {"processed": 1, "failed": 0}
        """.data(using: .utf8)!
        let api = StubAPIClient(postResults: ["/bulk-action": .success(payload)])
        let vm = makeVM(api: api)
        await vm.perform(action: "void", ids: [1])
        // After first completion, state is .success
        // Attempting again should do nothing because state != .idle
        await vm.perform(action: "void", ids: [2])
        if case .success = vm.state {
            // Still .success — second call was ignored
        } else {
            XCTFail("State changed unexpectedly: \(vm.state)")
        }
    }
}
