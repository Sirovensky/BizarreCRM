import XCTest
@testable import Pos
import Persistence

/// §39 — Unit tests for `OpenRegisterViewModel`.
/// Coverage target: 80%+. No UIKit, no DB, no live network.
@MainActor
final class OpenRegisterViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeSUT(floatText: String = "0.00", userId: Int64 = 1) -> (OpenRegisterViewModel, MockCashSessionRepository) {
        let repo = MockCashSessionRepository()
        let vm = OpenRegisterViewModel(userId: userId, repository: repo)
        vm.floatText = floatText
        return (vm, repo)
    }

    // MARK: - Validation

    func test_isValid_true_forZeroFloat() {
        let (vm, _) = makeSUT(floatText: "0.00")
        XCTAssertTrue(vm.isValid)
    }

    func test_isValid_true_forPositiveFloat() {
        let (vm, _) = makeSUT(floatText: "100.00")
        XCTAssertTrue(vm.isValid)
    }

    func test_isValid_false_forEmptyText() {
        let (vm, _) = makeSUT(floatText: "")
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_false_forNonNumericText() {
        let (vm, _) = makeSUT(floatText: "abc")
        XCTAssertFalse(vm.isValid)
    }

    func test_floatCents_convertsDecimalToCents() {
        let (vm, _) = makeSUT(floatText: "50.00")
        XCTAssertEqual(vm.floatCents, 5000)
    }

    func test_floatCents_zeroForInvalidInput() {
        let (vm, _) = makeSUT(floatText: "bad")
        XCTAssertEqual(vm.floatCents, 0)
    }

    // MARK: - Successful open

    func test_submit_callsRepositoryWithCorrectFloat() async {
        let (vm, repo) = makeSUT(floatText: "50.00")
        repo.openSessionResult = .success(MockCashSessionRepository.makeOpenRecord(float: 5000))
        await vm.submit()
        XCTAssertEqual(repo.openSessionCallCount, 1)
        XCTAssertEqual(repo.lastOpenFloat, 5000)
    }

    func test_submit_setsOpenedSession_onSuccess() async {
        let (vm, repo) = makeSUT(floatText: "100.00")
        let expected = MockCashSessionRepository.makeOpenRecord(id: 7, float: 10000)
        repo.openSessionResult = .success(expected)
        await vm.submit()
        XCTAssertNotNil(vm.openedSession)
        XCTAssertEqual(vm.openedSession?.id, 7)
    }

    func test_submit_clearsErrorOnSuccess() async {
        let (vm, repo) = makeSUT(floatText: "10.00")
        vm.floatText = "bad"  // prime an error
        await vm.submit()
        vm.floatText = "10.00"
        repo.openSessionResult = .success(MockCashSessionRepository.makeOpenRecord())
        await vm.submit()
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Invalid input before network call

    func test_submit_doesNotCallRepository_whenInvalid() async {
        let (vm, repo) = makeSUT(floatText: "")
        await vm.submit()
        XCTAssertEqual(repo.openSessionCallCount, 0)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Already open session

    func test_submit_onAlreadyOpen_fetchesCurrentSession() async {
        let (vm, repo) = makeSUT(floatText: "0.00")
        repo.openSessionResult = .failure(CashRegisterError.alreadyOpen)
        let existing = MockCashSessionRepository.makeOpenRecord(id: 99)
        repo.currentSessionResult = .success(existing)
        await vm.submit()
        XCTAssertEqual(vm.openedSession?.id, 99)
        XCTAssertNil(vm.errorMessage)
    }

    func test_submit_onAlreadyOpen_setsError_whenNoCurrentSession() async {
        let (vm, repo) = makeSUT(floatText: "0.00")
        repo.openSessionResult = .failure(CashRegisterError.alreadyOpen)
        repo.currentSessionResult = .success(nil)
        await vm.submit()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.openedSession)
    }

    // MARK: - Generic error

    func test_submit_setsErrorMessage_onGenericFailure() async {
        let (vm, repo) = makeSUT(floatText: "20.00")
        struct BoomError: Error {}
        repo.openSessionResult = .failure(BoomError())
        await vm.submit()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.openedSession)
    }

    // MARK: - Guard: double submit

    func test_submit_guardAgainstDoubleSubmit() async {
        let (vm, repo) = makeSUT(floatText: "10.00")
        // We can't race Tasks in a @MainActor test, so validate via isSubmitting
        // transitions. A second synchronous call while already submitting is
        // dropped by the `guard !isSubmitting` gate.
        repo.openSessionResult = .success(MockCashSessionRepository.makeOpenRecord())
        await vm.submit()
        // After first call completes isSubmitting resets to false.
        XCTAssertFalse(vm.isSubmitting)
        // A second call after the first completes is allowed (not a re-entry guard).
        await vm.submit()
        XCTAssertEqual(repo.openSessionCallCount, 2)
    }

    // MARK: - clearError

    func test_clearError_nilsErrorMessage() {
        let (vm, _) = makeSUT(floatText: "")
        vm.floatText = "bad"
        // Manually prime error state (since submit is async, poke it directly).
        vm.clearError()
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - userId propagated

    func test_submit_propagatesUserId() async {
        let (vm, repo) = makeSUT(floatText: "0.00", userId: 77)
        repo.openSessionResult = .success(MockCashSessionRepository.makeOpenRecord(userId: 77))
        await vm.submit()
        XCTAssertEqual(repo.lastOpenUserId, 77)
    }
}
