import XCTest
@testable import DataImport

// MARK: - ImportContextMenuTests

final class ImportContextMenuTests: XCTestCase {

    // MARK: - ImportRowAction equality / identity

    func test_retryAction_rowIdentity() {
        let action = ImportRowAction.retryRow(5)
        if case .retryRow(let row) = action {
            XCTAssertEqual(row, 5)
        } else {
            XCTFail("Expected .retryRow(5)")
        }
    }

    func test_skipAction_rowIdentity() {
        let action = ImportRowAction.skipRow(12)
        if case .skipRow(let row) = action {
            XCTAssertEqual(row, 12)
        } else {
            XCTFail("Expected .skipRow(12)")
        }
    }

    func test_copyErrorAction_reasonCapture() {
        let reason = "Invalid email format"
        let action = ImportRowAction.copyError(reason)
        if case .copyError(let text) = action {
            XCTAssertEqual(text, reason)
        } else {
            XCTFail("Expected .copyError")
        }
    }

    // MARK: - ViewModel row actions

    @MainActor
    func test_retryRow_removesErrorFromList() async {
        let repo = MockImportRepository()
        await repo.set(errorsResult: .success([
            ImportRowError(row: 1, column: "email", reason: "Bad email"),
            ImportRowError(row: 2, column: "email", reason: "Duplicate"),
            ImportRowError(row: 3, column: nil,     reason: "Missing row"),
        ]))
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        vm.jobId = "job-1"
        await vm.viewErrors()

        XCTAssertEqual(vm.rowErrors.count, 3)

        vm.retryRow(2)

        XCTAssertEqual(vm.rowErrors.count, 2)
        XCTAssertFalse(vm.rowErrors.contains { $0.row == 2 })
    }

    @MainActor
    func test_skipRow_removesErrorFromList() async {
        let repo = MockImportRepository()
        await repo.set(errorsResult: .success([
            ImportRowError(row: 7, column: "phone", reason: "Not a phone number"),
            ImportRowError(row: 9, column: nil,     reason: "Empty row"),
        ]))
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        vm.jobId = "job-1"
        await vm.viewErrors()

        vm.skipRow(7)

        XCTAssertEqual(vm.rowErrors.count, 1)
        XCTAssertEqual(vm.rowErrors.first?.row, 9)
    }

    @MainActor
    func test_retryRow_noMatchIsNoop() async {
        let repo = MockImportRepository()
        await repo.set(errorsResult: .success([ImportRowError(row: 1, column: nil, reason: "err")]))
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        vm.jobId = "job-1"
        await vm.viewErrors()

        vm.retryRow(999)

        XCTAssertEqual(vm.rowErrors.count, 1)
    }

    @MainActor
    func test_skipRow_noMatchIsNoop() async {
        let repo = MockImportRepository()
        await repo.set(errorsResult: .success([ImportRowError(row: 3, column: nil, reason: "err")]))
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        vm.jobId = "job-1"
        await vm.viewErrors()

        vm.skipRow(999)

        XCTAssertEqual(vm.rowErrors.count, 1)
    }

    @MainActor
    func test_multipleRetries_idempotent() async {
        let repo = MockImportRepository()
        await repo.set(errorsResult: .success([ImportRowError(row: 4, column: nil, reason: "err")]))
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        vm.jobId = "job-1"
        await vm.viewErrors()

        vm.retryRow(4)
        vm.retryRow(4)

        XCTAssertEqual(vm.rowErrors.count, 0)
    }
}
