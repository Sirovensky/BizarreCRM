import XCTest
@testable import Inventory

// MARK: - PurchaseOrderDetailViewModelTests

@MainActor
final class PurchaseOrderDetailViewModelTests: XCTestCase {

    // MARK: load()

    func test_load_success_setsOrder() async {
        let repo = MockPurchaseOrderRepository()
        repo.getResult = .success(MockPOFixtures.draft)
        let supplierRepo = MockSupplierRepository()
        let vm = makeVM(id: 100, repo: repo, supplierRepo: supplierRepo)

        await vm.load()

        XCTAssertEqual(vm.order?.id, 100)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    func test_load_alsoFetchesSupplier() async {
        let repo = MockPurchaseOrderRepository()
        let supplierRepo = MockSupplierRepository()
        let vm = makeVM(id: 100, repo: repo, supplierRepo: supplierRepo)

        await vm.load()

        XCTAssertEqual(supplierRepo.getCallCount, 1)
        XCTAssertNotNil(vm.order)
    }

    func test_load_supplierFetchFails_stillSetsOrder() async {
        let repo = MockPurchaseOrderRepository()
        let supplierRepo = MockSupplierRepository()
        supplierRepo.getResult = .failure(MockError.generic)
        let vm = makeVM(id: 100, repo: repo, supplierRepo: supplierRepo)

        await vm.load()

        XCTAssertNotNil(vm.order)
        // No error — supplier is optional
        XCTAssertNil(vm.errorMessage)
    }

    func test_load_networkError_setsErrorMessage() async {
        let repo = MockPurchaseOrderRepository()
        repo.getResult = .failure(MockError.generic)
        let supplierRepo = MockSupplierRepository()
        let vm = makeVM(id: 100, repo: repo, supplierRepo: supplierRepo)

        await vm.load()

        XCTAssertNil(vm.order)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: approveOrder()

    func test_approveOrder_draftPO_callsRepoApprove() async {
        let repo = MockPurchaseOrderRepository()
        repo.getResult = .success(MockPOFixtures.draft)
        repo.approveResult = .success(MockPOFixtures.pending)
        let vm = makeVM(id: 100, repo: repo)
        await vm.load()

        await vm.approveOrder()

        XCTAssertEqual(repo.approveCallCount, 1)
        XCTAssertEqual(repo.approveLastId, 100)
        XCTAssertEqual(vm.order?.status, .pending)
        XCTAssertNil(vm.errorMessage)
    }

    func test_approveOrder_nonDraftPO_doesNotCallRepo() async {
        let repo = MockPurchaseOrderRepository()
        repo.getResult = .success(MockPOFixtures.pending)
        let vm = makeVM(id: 100, repo: repo)
        await vm.load()

        await vm.approveOrder()

        XCTAssertEqual(repo.approveCallCount, 0)
    }

    func test_approveOrder_nilOrder_doesNotCallRepo() async {
        let repo = MockPurchaseOrderRepository()
        let vm = makeVM(id: 100, repo: repo)
        // don't call load — order stays nil

        await vm.approveOrder()

        XCTAssertEqual(repo.approveCallCount, 0)
    }

    func test_approveOrder_networkError_setsErrorMessage() async {
        let repo = MockPurchaseOrderRepository()
        repo.getResult = .success(MockPOFixtures.draft)
        repo.approveResult = .failure(MockError.generic)
        let vm = makeVM(id: 100, repo: repo)
        await vm.load()

        await vm.approveOrder()

        XCTAssertNotNil(vm.errorMessage)
        // order unchanged (still draft from load)
        XCTAssertEqual(vm.order?.status, .draft)
    }

    // MARK: cancelOrder()

    func test_cancelOrder_openPO_callsRepoCancel() async {
        let repo = MockPurchaseOrderRepository()
        repo.getResult = .success(MockPOFixtures.draft)
        repo.cancelResult = .success(MockPOFixtures.cancelled)
        let vm = makeVM(id: 100, repo: repo)
        await vm.load()

        await vm.cancelOrder()

        XCTAssertEqual(repo.cancelCallCount, 1)
        XCTAssertEqual(repo.cancelLastId, 100)
        XCTAssertEqual(vm.order?.status, .cancelled)
        XCTAssertNil(vm.errorMessage)
    }

    func test_cancelOrder_withReason_passesThroughReason() async {
        let repo = MockPurchaseOrderRepository()
        repo.getResult = .success(MockPOFixtures.pending)
        repo.cancelResult = .success(MockPOFixtures.cancelled)
        let vm = makeVM(id: 100, repo: repo)
        await vm.load()

        await vm.cancelOrder(reason: "Duplicate order")

        XCTAssertEqual(repo.cancelLastReason, "Duplicate order")
    }

    func test_cancelOrder_terminalPO_doesNotCallRepo() async {
        let repo = MockPurchaseOrderRepository()
        repo.getResult = .success(MockPOFixtures.received)
        let vm = makeVM(id: 100, repo: repo)
        await vm.load()

        await vm.cancelOrder()

        XCTAssertEqual(repo.cancelCallCount, 0)
    }

    func test_cancelOrder_alreadyCancelled_doesNotCallRepo() async {
        let repo = MockPurchaseOrderRepository()
        repo.getResult = .success(MockPOFixtures.cancelled)
        let vm = makeVM(id: 100, repo: repo)
        await vm.load()

        await vm.cancelOrder()

        XCTAssertEqual(repo.cancelCallCount, 0)
    }

    func test_cancelOrder_networkError_setsErrorMessage() async {
        let repo = MockPurchaseOrderRepository()
        repo.getResult = .success(MockPOFixtures.draft)
        repo.cancelResult = .failure(MockError.generic)
        let vm = makeVM(id: 100, repo: repo)
        await vm.load()

        await vm.cancelOrder()

        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Helpers

    private func makeVM(
        id: Int64 = 100,
        repo: MockPurchaseOrderRepository? = nil,
        supplierRepo: MockSupplierRepository? = nil
    ) -> PurchaseOrderDetailViewModel {
        PurchaseOrderDetailViewModel(
            orderId: id,
            repo: repo ?? MockPurchaseOrderRepository(),
            supplierRepo: supplierRepo ?? MockSupplierRepository()
        )
    }
}
