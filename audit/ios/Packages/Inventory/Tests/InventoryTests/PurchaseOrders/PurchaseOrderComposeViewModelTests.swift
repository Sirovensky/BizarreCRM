import XCTest
@testable import Inventory

// MARK: - PurchaseOrderComposeViewModelTests

@MainActor
final class PurchaseOrderComposeViewModelTests: XCTestCase {

    // MARK: loadSuppliers()

    func test_loadSuppliers_success_populatesSuppliers() async {
        let repo = MockPurchaseOrderRepository()
        let supplierRepo = MockSupplierRepository()
        supplierRepo.listResult = .success([MockPOFixtures.supplier])
        let vm = makeVM(repo: repo, supplierRepo: supplierRepo)

        await vm.loadSuppliers()

        XCTAssertEqual(vm.suppliers.count, 1)
        XCTAssertEqual(vm.selectedSupplierId, MockPOFixtures.supplier.id)
        XCTAssertNil(vm.errorMessage)
    }

    func test_loadSuppliers_failure_setsErrorMessage() async {
        let supplierRepo = MockSupplierRepository()
        supplierRepo.listResult = .failure(MockError.generic)
        let vm = makeVM(supplierRepo: supplierRepo)

        await vm.loadSuppliers()

        XCTAssertTrue(vm.suppliers.isEmpty)
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_loadSuppliers_emptyList_noAutoSelection() async {
        let supplierRepo = MockSupplierRepository()
        supplierRepo.listResult = .success([])
        let vm = makeVM(supplierRepo: supplierRepo)

        await vm.loadSuppliers()

        XCTAssertNil(vm.selectedSupplierId)
    }

    // MARK: addLine / removeLine

    func test_addLine_appendsDraftLine() {
        let vm = makeVM()
        let initialCount = vm.lines.count

        vm.addLine()

        XCTAssertEqual(vm.lines.count, initialCount + 1)
    }

    func test_removeLine_atOffset_removesDraftLine() {
        let vm = makeVM()
        vm.addLine()
        vm.addLine()
        let count = vm.lines.count

        vm.removeLine(at: IndexSet(integer: 0))

        XCTAssertEqual(vm.lines.count, count - 1)
    }

    // MARK: estimatedTotal

    func test_estimatedTotal_singleLine() {
        let vm = makeVM()
        vm.lines = [
            DraftPOLine(sku: "A", name: "Apple", qty: "3", unitCostCents: "200")
        ]

        XCTAssertEqual(vm.estimatedTotal, 600)
    }

    func test_estimatedTotal_multipleLines() {
        let vm = makeVM()
        vm.lines = [
            DraftPOLine(sku: "A", name: "Apple",  qty: "2", unitCostCents: "500"),
            DraftPOLine(sku: "B", name: "Banana", qty: "5", unitCostCents: "100")
        ]

        XCTAssertEqual(vm.estimatedTotal, 1500)
    }

    func test_estimatedTotal_invalidQty_treatsAsZero() {
        let vm = makeVM()
        vm.lines = [
            DraftPOLine(sku: "A", name: "Apple", qty: "abc", unitCostCents: "200")
        ]

        XCTAssertEqual(vm.estimatedTotal, 0)
    }

    func test_estimatedTotal_invalidCost_treatsAsZero() {
        let vm = makeVM()
        vm.lines = [
            DraftPOLine(sku: "A", name: "Apple", qty: "3", unitCostCents: "xyz")
        ]

        XCTAssertEqual(vm.estimatedTotal, 0)
    }

    // MARK: isValid

    func test_isValid_noSupplier_returnsFalse() {
        let vm = makeVM()
        vm.selectedSupplierId = nil
        vm.lines = [DraftPOLine(sku: "A", name: "Apple")]

        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_noLines_returnsFalse() {
        let vm = makeVM()
        vm.selectedSupplierId = 1
        vm.lines = []

        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_lineWithEmptySku_returnsFalse() {
        let vm = makeVM()
        vm.selectedSupplierId = 1
        vm.lines = [DraftPOLine(sku: "", name: "Apple")]

        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_lineWithEmptyName_returnsFalse() {
        let vm = makeVM()
        vm.selectedSupplierId = 1
        vm.lines = [DraftPOLine(sku: "A", name: "")]

        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_allFieldsPopulated_returnsTrue() {
        let vm = makeVM()
        vm.selectedSupplierId = 1
        vm.lines = [DraftPOLine(sku: "A", name: "Apple", qty: "1", unitCostCents: "100")]

        XCTAssertTrue(vm.isValid)
    }

    // MARK: submit()

    func test_submit_validForm_callsRepoCreate() async {
        let repo = MockPurchaseOrderRepository()
        repo.createResult = .success(MockPOFixtures.draft)
        let vm = makeVM(repo: repo)
        vm.selectedSupplierId = 1
        vm.lines = [DraftPOLine(sku: "A", name: "Widget", qty: "2", unitCostCents: "500")]

        let ok = await vm.submit()

        XCTAssertTrue(ok)
        XCTAssertEqual(repo.createCallCount, 1)
        XCTAssertNil(vm.errorMessage)
    }

    func test_submit_invalidForm_returnsFalseWithoutCallingRepo() async {
        let repo = MockPurchaseOrderRepository()
        let vm = makeVM(repo: repo)
        vm.selectedSupplierId = nil  // invalid

        let ok = await vm.submit()

        XCTAssertFalse(ok)
        XCTAssertEqual(repo.createCallCount, 0)
    }

    func test_submit_networkError_returnsFalseAndSetsError() async {
        let repo = MockPurchaseOrderRepository()
        repo.createResult = .failure(MockError.generic)
        let vm = makeVM(repo: repo)
        vm.selectedSupplierId = 1
        vm.lines = [DraftPOLine(sku: "A", name: "Widget")]

        let ok = await vm.submit()

        XCTAssertFalse(ok)
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_submit_withExpectedDate_includesDateInRequest() async {
        let repo = MockPurchaseOrderRepository()
        let vm = makeVM(repo: repo)
        vm.selectedSupplierId = 1
        vm.lines = [DraftPOLine(sku: "A", name: "Widget")]
        vm.hasExpectedDate = true
        vm.expectedDate = Date(timeIntervalSinceReferenceDate: 1_000_000)

        _ = await vm.submit()

        XCTAssertEqual(repo.createCallCount, 1)
    }

    func test_submit_withoutExpectedDate_passesNilDate() async {
        let repo = MockPurchaseOrderRepository()
        let vm = makeVM(repo: repo)
        vm.selectedSupplierId = 1
        vm.lines = [DraftPOLine(sku: "A", name: "Widget")]
        vm.hasExpectedDate = false

        _ = await vm.submit()

        XCTAssertEqual(repo.createCallCount, 1)
    }

    // MARK: - Helpers

    private func makeVM(
        repo: MockPurchaseOrderRepository? = nil,
        supplierRepo: MockSupplierRepository? = nil
    ) -> PurchaseOrderComposeViewModel {
        PurchaseOrderComposeViewModel(
            repo: repo ?? MockPurchaseOrderRepository(),
            supplierRepo: supplierRepo ?? MockSupplierRepository()
        )
    }
}
