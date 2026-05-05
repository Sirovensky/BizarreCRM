import XCTest
@testable import Expenses
@testable import Networking

// MARK: - Expense Detail Delete / Receipt tests

@MainActor
final class ExpenseDetailDeleteTests: XCTestCase {

    // MARK: - Initial state

    func testInitialDeleteState() {
        let api = MockAPIClient()
        let vm = ExpenseDetailViewModel(api: api, id: 1)
        XCTAssertFalse(vm.isDeleting)
        XCTAssertFalse(vm.didDelete)
        XCTAssertNil(vm.deleteError)
    }

    // MARK: - Successful delete

    func testDeleteSetsDotDotDidDelete() async {
        let api = MockAPIClient()
        await api.setDeleteOutcome(.success)
        let vm = ExpenseDetailViewModel(api: api, id: 1)
        await vm.delete()
        XCTAssertTrue(vm.didDelete)
        XCTAssertFalse(vm.isDeleting)
        XCTAssertNil(vm.deleteError)
    }

    func testDeleteCallsAPIOnce() async {
        let api = MockAPIClient()
        await api.setDeleteOutcome(.success)
        let vm = ExpenseDetailViewModel(api: api, id: 1)
        await vm.delete()
        let count = await api.deleteCallCount
        XCTAssertEqual(count, 1)
    }

    // MARK: - Failed delete

    func testDeleteFailureSetsError() async {
        let api = MockAPIClient()
        await api.setDeleteOutcome(.failure(MockError.network))
        let vm = ExpenseDetailViewModel(api: api, id: 1)
        await vm.delete()
        XCTAssertNotNil(vm.deleteError)
        XCTAssertFalse(vm.didDelete)
    }

    func testDeleteFailureMessageMatchesError() async {
        let api = MockAPIClient()
        await api.setDeleteOutcome(.failure(MockError.network))
        let vm = ExpenseDetailViewModel(api: api, id: 1)
        await vm.delete()
        XCTAssertEqual(vm.deleteError, MockError.network.localizedDescription)
    }

    // MARK: - Delete clears error from previous attempt

    func testDeleteClearsPreviousError() async {
        let api = MockAPIClient()
        await api.setDeleteOutcome(.failure(MockError.network))
        let vm = ExpenseDetailViewModel(api: api, id: 1)
        await vm.delete()
        XCTAssertNotNil(vm.deleteError)

        // Second attempt succeeds
        await api.setDeleteOutcome(.success)
        await vm.delete()
        XCTAssertNil(vm.deleteError)
        XCTAssertTrue(vm.didDelete)
    }

    // MARK: - Load + delete state integration

    func testDeleteDoesNotAffectLoadedState() async {
        let api = MockAPIClient()
        await api.setOutcome(.success(Expense.fixture()))
        await api.setDeleteOutcome(.success)
        let vm = ExpenseDetailViewModel(api: api, id: 1)
        await vm.load()
        guard case .loaded = vm.state else {
            return XCTFail("Expected loaded state after load()")
        }
        // Delete doesn't change the loaded state (navigation dismisses the view)
        await vm.delete()
        XCTAssertTrue(vm.didDelete)
        guard case .loaded = vm.state else {
            return XCTFail("Loaded state should be preserved after delete")
        }
    }

    // MARK: - refreshAfterReceiptAttach

    func testRefreshAfterReceiptAttachRefreshs() async {
        let api = MockAPIClient()
        let withReceipt = Expense.fixture(receiptImagePath: "/uploads/receipts/new.jpg")
        await api.setOutcome(.success(withReceipt))
        let vm = ExpenseDetailViewModel(api: api, id: 1)
        await vm.refreshAfterReceiptAttach()
        if case .loaded(let exp) = vm.state {
            XCTAssertEqual(exp.receiptImagePath, "/uploads/receipts/new.jpg")
        } else {
            XCTFail("Expected loaded state with receipt path")
        }
    }
}
