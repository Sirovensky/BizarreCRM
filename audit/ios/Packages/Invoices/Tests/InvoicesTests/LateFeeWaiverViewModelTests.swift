import XCTest
@testable import Invoices
import Networking
import Core

// §7.7 LateFeeWaiverViewModel tests
// Covers: initial state, isValid, requiresManagerPin, PIN gate, submit, error mapping.

@MainActor
final class LateFeeWaiverViewModelTests: XCTestCase {

    private func makeSut(
        api: StubAPIClient = StubAPIClient(),
        maxWaiverCents: Int = 3_000
    ) -> LateFeeWaiverViewModel {
        LateFeeWaiverViewModel(api: api, invoiceId: 10, maxWaiverCents: maxWaiverCents)
    }

    // MARK: - Initial state

    func test_initialState_isIdle() {
        let vm = makeSut()
        guard case .idle = vm.state else {
            XCTFail("Expected .idle")
            return
        }
    }

    func test_initialAmount_preseedWithMax() {
        let vm = makeSut(maxWaiverCents: 2_500)
        XCTAssertEqual(vm.amountCents, 2_500)
    }

    func test_initialReason_isEmpty() {
        XCTAssertTrue(makeSut().reason.isEmpty)
    }

    // MARK: - requiresManagerPin

    func test_requiresManagerPin_falseBelow5000() {
        let vm = makeSut(maxWaiverCents: 10_000)
        vm.amountCents = 4_999
        XCTAssertFalse(vm.requiresManagerPin)
    }

    func test_requiresManagerPin_falseAt5000() {
        let vm = makeSut(maxWaiverCents: 10_000)
        vm.amountCents = 5_000
        XCTAssertFalse(vm.requiresManagerPin)
    }

    func test_requiresManagerPin_trueAbove5000() {
        let vm = makeSut(maxWaiverCents: 10_000)
        vm.amountCents = 5_001
        XCTAssertTrue(vm.requiresManagerPin)
    }

    // MARK: - isValid

    func test_isValid_falseWhenAmountZero() {
        let vm = makeSut(maxWaiverCents: 3_000)
        vm.amountCents = 0
        vm.reason = "Goodwill"
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_falseWhenReasonEmpty() {
        let vm = makeSut(maxWaiverCents: 3_000)
        vm.reason = ""
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_falseWhenAmountExceedsMax() {
        let vm = makeSut(maxWaiverCents: 3_000)
        vm.amountCents = 4_000
        vm.reason = "Customer complained"
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_trueWhenAmountAndReasonOk() {
        let vm = makeSut(maxWaiverCents: 3_000)
        vm.amountCents = 1_500
        vm.reason = "One-time goodwill"
        XCTAssertTrue(vm.isValid)
    }

    // MARK: - Submit

    func test_submit_highAmount_triggersManagerPinPrompt() async {
        let vm = makeSut(api: .waiverSuccess(), maxWaiverCents: 10_000)
        vm.amountCents = 6_000
        vm.reason = "VIP customer"
        await vm.submit()
        XCTAssertTrue(vm.showManagerPinPrompt)
        guard case .idle = vm.state else {
            XCTFail("Expected .idle while waiting for PIN")
            return
        }
    }

    func test_submitWithPin_succeeds() async {
        let vm = makeSut(api: .waiverSuccess(), maxWaiverCents: 10_000)
        vm.amountCents = 6_000
        vm.reason = "Long-standing customer"
        await vm.submitWithPin("4321")
        guard case .success = vm.state else {
            XCTFail("Expected .success after PIN")
            return
        }
    }

    func test_submit_smallAmount_succeedsWithoutPin() async {
        let vm = makeSut(api: .waiverSuccess(), maxWaiverCents: 3_000)
        vm.amountCents = 2_000
        vm.reason = "Error in billing"
        await vm.submit()
        guard case .success = vm.state else {
            XCTFail("Expected .success")
            return
        }
    }

    // MARK: - resetToIdle

    func test_resetToIdle_fromFailed_becomesIdle() async {
        let vm = makeSut(api: .waiverFailure(AppError.server(statusCode: 500, message: "test")), maxWaiverCents: 3_000)
        vm.amountCents = 1_000
        vm.reason = "Test"
        await vm.submit()
        vm.resetToIdle()
        guard case .idle = vm.state else {
            XCTFail("Expected .idle after reset")
            return
        }
    }

    // MARK: - kLateFeeWaiverManagerPinThresholdCents

    func test_threshold_is5000Cents() {
        XCTAssertEqual(kLateFeeWaiverManagerPinThresholdCents, 5_000)
    }
}

// MARK: - StubAPIClient waiver extensions

extension StubAPIClient {
    static func waiverSuccess() -> StubAPIClient {
        let payload = """
        {"success":true,"message":"Late fee waived"}
        """.data(using: .utf8)!
        return StubAPIClient(postResults: ["/waive-late-fee": .success(payload)])
    }

    static func waiverFailure(_ error: Error) -> StubAPIClient {
        StubAPIClient(postResults: ["/waive-late-fee": .failure(error)])
    }
}
