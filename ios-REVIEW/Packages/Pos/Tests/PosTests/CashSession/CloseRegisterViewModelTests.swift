import XCTest
@testable import Pos
import Persistence

/// §39 — Unit tests for `CloseRegisterViewModel`.
/// Coverage target: 80%+. No UIKit, no DB, no live network.
@MainActor
final class CloseRegisterViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeSession(
        id: Int64 = 1,
        openingFloat: Int = 5000
    ) -> CashSessionRecord {
        MockCashSessionRepository.makeOpenRecord(id: id, float: openingFloat)
    }

    private func makeSUT(
        session: CashSessionRecord? = nil,
        closedBy: Int64 = 42
    ) -> (CloseRegisterViewModel, MockCashSessionRepository) {
        let repo = MockCashSessionRepository()
        let s = session ?? makeSession()
        let vm = CloseRegisterViewModel(session: s, closedBy: closedBy, repository: repo)
        return (vm, repo)
    }

    // MARK: - Initial state

    func test_initialExpectedCents_equalsOpeningFloat() {
        let (vm, _) = makeSUT(session: makeSession(openingFloat: 7500))
        XCTAssertEqual(vm.expectedCents, 7500)
    }

    func test_initialCountedCents_isZero() {
        let (vm, _) = makeSUT()
        XCTAssertEqual(vm.countedCents, 0)
    }

    func test_initialCanSubmit_isFalse() {
        let (vm, _) = makeSUT()
        XCTAssertFalse(vm.canSubmit)
    }

    // MARK: - countedCents derivation

    func test_countedCents_parsesDecimalText() {
        let (vm, _) = makeSUT()
        vm.countedText = "150.00"
        XCTAssertEqual(vm.countedCents, 15000)
    }

    func test_countedCents_zeroForEmptyText() {
        let (vm, _) = makeSUT()
        vm.countedText = ""
        XCTAssertEqual(vm.countedCents, 0)
    }

    func test_countedCents_zeroForNonNumericText() {
        let (vm, _) = makeSUT()
        vm.countedText = "xyz"
        XCTAssertEqual(vm.countedCents, 0)
    }

    // MARK: - varianceCents

    func test_varianceCents_positiveWhenOverCounted() {
        let (vm, _) = makeSUT(session: makeSession(openingFloat: 10000))
        vm.countedText = "150.00"   // 15000 cents
        // expectedCents stays at 10000 until loadRegisterState succeeds
        XCTAssertEqual(vm.varianceCents, 5000)
    }

    func test_varianceCents_negativeWhenUnderCounted() {
        let (vm, _) = makeSUT(session: makeSession(openingFloat: 10000))
        vm.countedText = "50.00"    // 5000 cents
        XCTAssertEqual(vm.varianceCents, -5000)
    }

    func test_varianceCents_zeroWhenBalanced() {
        let (vm, _) = makeSUT(session: makeSession(openingFloat: 10000))
        vm.countedText = "100.00"
        XCTAssertEqual(vm.varianceCents, 0)
    }

    // MARK: - varianceBand

    func test_varianceBand_green_whenBalanced() {
        let (vm, _) = makeSUT(session: makeSession(openingFloat: 10000))
        vm.countedText = "100.00"
        XCTAssertEqual(vm.varianceBand, .green)
    }

    func test_varianceBand_amber_withinFiveDollars() {
        let (vm, _) = makeSUT(session: makeSession(openingFloat: 10000))
        vm.countedText = "103.00"   // +300 cents = amber
        XCTAssertEqual(vm.varianceBand, .amber)
    }

    func test_varianceBand_red_outsideFiveDollars() {
        let (vm, _) = makeSUT(session: makeSession(openingFloat: 10000))
        vm.countedText = "120.00"   // +1000 cents = red (> 500)
        XCTAssertEqual(vm.varianceBand, .red)
    }

    // MARK: - canSubmit

    func test_canSubmit_true_whenAmberNoNotes() {
        let (vm, _) = makeSUT(session: makeSession(openingFloat: 10000))
        vm.countedText = "103.00"
        vm.notes = ""
        XCTAssertTrue(vm.canSubmit)
    }

    func test_canSubmit_false_whenRedNoNotes() {
        let (vm, _) = makeSUT(session: makeSession(openingFloat: 10000))
        vm.countedText = "120.00"
        vm.notes = ""
        XCTAssertFalse(vm.canSubmit)
    }

    func test_canSubmit_true_whenRedWithNotes() {
        let (vm, _) = makeSUT(session: makeSession(openingFloat: 10000))
        vm.countedText = "120.00"
        vm.notes = "Till drop"
        XCTAssertTrue(vm.canSubmit)
    }

    func test_canSubmit_false_whenCountedTextEmpty() {
        let (vm, _) = makeSUT()
        vm.countedText = ""
        XCTAssertFalse(vm.canSubmit)
    }

    // MARK: - loadRegisterState

    func test_loadRegisterState_updatesExpectedCents() async {
        let (vm, repo) = makeSUT(session: makeSession(openingFloat: 5000))
        repo.fetchRegisterStateResult = .success(
            RegisterStateDTO(cashIn: 1000, cashOut: 200, cashSales: 3000, net: 3800, entries: [])
        )
        await vm.loadRegisterState()
        // expected = float(5000) + cashSales(3000) + cashIn(1000) - cashOut(200) = 8800
        XCTAssertEqual(vm.expectedCents, 8800)
    }

    func test_loadRegisterState_callsRepository() async {
        let (vm, repo) = makeSUT()
        await vm.loadRegisterState()
        XCTAssertEqual(repo.fetchRegisterStateCallCount, 1)
    }

    func test_loadRegisterState_setsErrorMessage_onFailure() async {
        let (vm, repo) = makeSUT()
        struct NetErr: Error {}
        repo.fetchRegisterStateResult = .failure(NetErr())
        await vm.loadRegisterState()
        XCTAssertNotNil(vm.errorMessage)
        // expected stays at opening float
        XCTAssertEqual(vm.expectedCents, 5000)
    }

    func test_loadRegisterState_doesNotOverrideExpected_onFailure() async {
        let (vm, repo) = makeSUT(session: makeSession(openingFloat: 2000))
        struct NetErr: Error {}
        repo.fetchRegisterStateResult = .failure(NetErr())
        await vm.loadRegisterState()
        XCTAssertEqual(vm.expectedCents, 2000)
    }

    // MARK: - close

    func test_close_callsRepositoryWithCorrectValues() async {
        let (vm, repo) = makeSUT(session: makeSession(openingFloat: 10000))
        vm.countedText = "103.00"
        vm.notes = "All good"
        repo.closeSessionResult = .success(MockCashSessionRepository.makeClosedRecord())
        await vm.close()
        XCTAssertEqual(repo.closeSessionCallCount, 1)
        XCTAssertEqual(repo.lastCloseCounted, 10300)
        XCTAssertEqual(repo.lastCloseNotes, "All good")
    }

    func test_close_setsClosedSession_onSuccess() async {
        let (vm, repo) = makeSUT(session: makeSession(openingFloat: 10000))
        vm.countedText = "100.00"
        let closed = MockCashSessionRepository.makeClosedRecord(id: 5)
        repo.closeSessionResult = .success(closed)
        await vm.close()
        XCTAssertEqual(vm.closedSession?.id, 5)
    }

    func test_close_doesNotCallRepository_whenCannotSubmit() async {
        let (vm, repo) = makeSUT()
        vm.countedText = ""
        await vm.close()
        XCTAssertEqual(repo.closeSessionCallCount, 0)
    }

    func test_close_setsError_whenNoOpenSession() async {
        let (vm, repo) = makeSUT(session: makeSession(openingFloat: 10000))
        vm.countedText = "100.00"
        repo.closeSessionResult = .failure(CashRegisterError.noOpenSession)
        await vm.close()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.closedSession)
    }

    func test_close_setsError_onGenericFailure() async {
        let (vm, repo) = makeSUT(session: makeSession(openingFloat: 10000))
        vm.countedText = "100.00"
        struct BoomError: Error { var localizedDescription: String { "Boom" } }
        repo.closeSessionResult = .failure(BoomError())
        await vm.close()
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_close_passesNilNotes_whenNotesIsBlank() async {
        let (vm, repo) = makeSUT(session: makeSession(openingFloat: 10000))
        vm.countedText = "100.00"
        vm.notes = "   "
        repo.closeSessionResult = .success(MockCashSessionRepository.makeClosedRecord())
        await vm.close()
        // blank → nil
        XCTAssertNil(repo.lastCloseNotes as? String)
    }

    // MARK: - notesRequired

    func test_notesRequired_false_forGreenBand() {
        let (vm, _) = makeSUT(session: makeSession(openingFloat: 10000))
        vm.countedText = "100.00"
        XCTAssertFalse(vm.notesRequired)
    }

    func test_notesRequired_false_forAmberBand() {
        let (vm, _) = makeSUT(session: makeSession(openingFloat: 10000))
        vm.countedText = "102.00"   // +200 cents amber
        XCTAssertFalse(vm.notesRequired)
    }

    func test_notesRequired_true_forRedBand() {
        let (vm, _) = makeSUT(session: makeSession(openingFloat: 10000))
        vm.countedText = "120.00"   // +1000 cents red
        XCTAssertTrue(vm.notesRequired)
    }

    // MARK: - clearError

    func test_clearError_nilsErrorMessage() async {
        let (vm, repo) = makeSUT()
        struct FakeErr: Error {}
        repo.fetchRegisterStateResult = .failure(FakeErr())
        await vm.loadRegisterState()
        XCTAssertNotNil(vm.errorMessage)
        vm.clearError()
        XCTAssertNil(vm.errorMessage)
    }
}
