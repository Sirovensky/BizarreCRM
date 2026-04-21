import XCTest
@testable import Invoices
import Networking
import Core

// §7.5 InvoiceVoidViewModel tests — state transitions, canVoid gate, validation.

@MainActor
final class InvoiceVoidViewModelTests: XCTestCase {

    private func makeSut(
        api: StubAPIClient = StubAPIClient(),
        invoiceId: Int64 = 1,
        canVoid: Bool = true
    ) -> InvoiceVoidViewModel {
        InvoiceVoidViewModel(api: api, invoiceId: invoiceId, canVoid: canVoid)
    }

    // MARK: - Initial state

    func test_initialState_isIdle() {
        let vm = makeSut()
        guard case .idle = vm.state else {
            XCTFail("Expected .idle, got \(vm.state)")
            return
        }
    }

    func test_initialReason_isEmpty() {
        let vm = makeSut()
        XCTAssertTrue(vm.reason.isEmpty)
    }

    // MARK: - isValid

    func test_isValid_trueWhenCanVoidAndReasonProvided() {
        let vm = makeSut(canVoid: true)
        vm.reason = "Customer request"
        XCTAssertTrue(vm.isValid)
    }

    func test_isValid_falseWhenReasonEmpty() {
        let vm = makeSut(canVoid: true)
        vm.reason = ""
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_falseWhenReasonOnlyWhitespace() {
        let vm = makeSut(canVoid: true)
        vm.reason = "   "
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_falseWhenCanVoidFalse() {
        let vm = makeSut(canVoid: false)
        vm.reason = "Some reason"
        XCTAssertFalse(vm.isValid)
    }

    // MARK: - submitVoid: canVoid = false

    func test_submitVoid_canVoidFalse_setsFailed() async {
        let vm = makeSut(canVoid: false)
        vm.reason = "Some reason"
        await vm.submitVoid()
        guard case let .failed(msg) = vm.state else {
            XCTFail("Expected .failed, got \(vm.state)")
            return
        }
        XCTAssertTrue(msg.lowercased().contains("cannot void") || msg.lowercased().contains("payment"))
    }

    // MARK: - submitVoid: empty reason

    func test_submitVoid_emptyReason_setsFailed() async {
        let vm = makeSut(canVoid: true)
        vm.reason = ""
        await vm.submitVoid()
        guard case .failed = vm.state else {
            XCTFail("Expected .failed for empty reason")
            return
        }
    }

    // MARK: - submitVoid: happy path

    func test_submitVoid_happyPath_transitionsToSuccess() async {
        let vm = makeSut(api: .voidSuccess(id: 55), canVoid: true)
        vm.reason = "Customer changed mind"
        await vm.submitVoid()
        guard case let .success(result) = vm.state else {
            XCTFail("Expected .success, got \(vm.state)")
            return
        }
        XCTAssertEqual(result.id, 55)
    }

    func test_submitVoid_success_statusIsVoid() async {
        let vm = makeSut(api: .voidSuccess(), canVoid: true)
        vm.reason = "Test void"
        await vm.submitVoid()
        guard case let .success(result) = vm.state else {
            XCTFail("Expected .success"); return
        }
        XCTAssertEqual(result.status, "void")
    }

    // MARK: - AppError mapping

    func test_submitVoid_conflict_showsVoidNotAllowedMessage() async {
        let err = AppError.conflict(reason: nil)
        let vm = makeSut(api: .voidFailure(err), canVoid: true)
        vm.reason = "Test"
        await vm.submitVoid()
        guard case let .failed(msg) = vm.state else {
            XCTFail("Expected .failed"); return
        }
        XCTAssertTrue(msg.lowercased().contains("void") || msg.lowercased().contains("payment"))
    }

    func test_submitVoid_forbidden_showsPermissionMessage() async {
        let err = AppError.forbidden(capability: nil)
        let vm = makeSut(api: .voidFailure(err), canVoid: true)
        vm.reason = "Test"
        await vm.submitVoid()
        guard case let .failed(msg) = vm.state else {
            XCTFail("Expected .failed"); return
        }
        XCTAssertTrue(msg.lowercased().contains("permission"))
    }

    func test_submitVoid_validationError_setsFieldErrors() async {
        let err = AppError.validation(fieldErrors: ["reason": "Too short"])
        let vm = makeSut(api: .voidFailure(err), canVoid: true)
        vm.reason = "x"
        await vm.submitVoid()
        XCTAssertFalse(vm.fieldErrors.isEmpty)
    }

    func test_submitVoid_networkError_setsFailed() async {
        let err = AppError.network(underlying: nil)
        let vm = makeSut(api: .voidFailure(err), canVoid: true)
        vm.reason = "Network test"
        await vm.submitVoid()
        guard case .failed = vm.state else {
            XCTFail("Expected .failed for network error")
            return
        }
    }

    // MARK: - resetToIdle

    func test_resetToIdle_fromFailed_becomesIdle() async {
        let err = AppError.conflict(reason: nil)
        let vm = makeSut(api: .voidFailure(err), canVoid: true)
        vm.reason = "Test"
        await vm.submitVoid()
        vm.resetToIdle()
        guard case .idle = vm.state else {
            XCTFail("Expected .idle after reset")
            return
        }
    }

    func test_resetToIdle_fromIdle_staysIdle() {
        let vm = makeSut()
        vm.resetToIdle()
        guard case .idle = vm.state else {
            XCTFail("Expected .idle")
            return
        }
    }

    // MARK: - canVoid property

    func test_canVoid_storedCorrectly() {
        let vmTrue = makeSut(canVoid: true)
        let vmFalse = makeSut(canVoid: false)
        XCTAssertTrue(vmTrue.canVoid)
        XCTAssertFalse(vmFalse.canVoid)
    }
}
