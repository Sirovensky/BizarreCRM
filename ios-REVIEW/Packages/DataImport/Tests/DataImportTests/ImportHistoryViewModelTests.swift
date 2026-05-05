import XCTest
@testable import DataImport

// MARK: - ImportHistoryViewModelTests
//
// Tests for ImportHistoryViewModel (the lightweight VM that backs
// ImportHistoryView). It has three responsibilities:
//   1. Load jobs from the repository on demand.
//   2. Expose isLoading during inflight requests.
//   3. Expose errorMessage on failure.
//
// MockImportRepository is defined in ImportWizardViewModelTests.swift and
// is available to all tests in this target via @testable import.

@MainActor
final class ImportHistoryViewModelTests: XCTestCase {

    // MARK: - Initial state

    func testInitialJobsAreEmpty() {
        let vm = ImportHistoryViewModel(repository: MockImportRepository())
        XCTAssertTrue(vm.jobs.isEmpty)
    }

    func testInitiallyNotLoading() {
        let vm = ImportHistoryViewModel(repository: MockImportRepository())
        XCTAssertFalse(vm.isLoading)
    }

    func testInitiallyNoError() {
        let vm = ImportHistoryViewModel(repository: MockImportRepository())
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Successful load

    func testLoadPopulatesJobs() async {
        let repo = MockImportRepository()
        let job1 = ImportJob.fixture(id: "j1", status: .completed)
        let job2 = ImportJob.fixture(id: "j2", status: .failed)
        await repo.set(listResult: .success([job1, job2]))
        let vm = ImportHistoryViewModel(repository: repo)
        await vm.load()
        XCTAssertEqual(vm.jobs.count, 2)
    }

    func testLoadSetsFirstJobId() async {
        let repo = MockImportRepository()
        let job = ImportJob.fixture(id: "first-job")
        await repo.set(listResult: .success([job]))
        let vm = ImportHistoryViewModel(repository: repo)
        await vm.load()
        XCTAssertEqual(vm.jobs.first?.id, "first-job")
    }

    func testLoadClearsErrorMessage() async {
        let repo = MockImportRepository()
        let vm = ImportHistoryViewModel(repository: repo)
        // Simulate a prior error
        await repo.set(listResult: .failure(MockImportRepository.Failure.simulated))
        await vm.load()
        // Now fix the repo and reload
        await repo.set(listResult: .success([.fixture()]))
        await vm.load()
        XCTAssertNil(vm.errorMessage)
    }

    func testLoadWithEmptyListSetsEmptyJobs() async {
        let repo = MockImportRepository()
        await repo.set(listResult: .success([]))
        let vm = ImportHistoryViewModel(repository: repo)
        await vm.load()
        XCTAssertTrue(vm.jobs.isEmpty)
        XCTAssertNil(vm.errorMessage)
    }

    func testLoadIsNotLoadingAfterSuccess() async {
        let repo = MockImportRepository()
        let vm = ImportHistoryViewModel(repository: repo)
        await vm.load()
        XCTAssertFalse(vm.isLoading)
    }

    func testLoadPreservesJobOrder() async {
        let repo = MockImportRepository()
        let jobs = [
            ImportJob.fixture(id: "a"),
            ImportJob.fixture(id: "b"),
            ImportJob.fixture(id: "c")
        ]
        await repo.set(listResult: .success(jobs))
        let vm = ImportHistoryViewModel(repository: repo)
        await vm.load()
        XCTAssertEqual(vm.jobs.map { $0.id }, ["a", "b", "c"])
    }

    // MARK: - Failure

    func testLoadFailureSetsErrorMessage() async {
        let repo = MockImportRepository()
        await repo.set(listResult: .failure(MockImportRepository.Failure.simulated))
        let vm = ImportHistoryViewModel(repository: repo)
        await vm.load()
        XCTAssertNotNil(vm.errorMessage)
    }

    func testLoadFailureDoesNotClearExistingJobs() async {
        let repo = MockImportRepository()
        // First load succeeds
        await repo.set(listResult: .success([.fixture(id: "kept")]))
        let vm = ImportHistoryViewModel(repository: repo)
        await vm.load()
        XCTAssertEqual(vm.jobs.count, 1)
        // Second load fails — jobs from first load are preserved
        await repo.set(listResult: .failure(MockImportRepository.Failure.simulated))
        await vm.load()
        XCTAssertEqual(vm.jobs.count, 1, "Jobs should survive a reload failure")
    }

    func testLoadIsNotLoadingAfterFailure() async {
        let repo = MockImportRepository()
        await repo.set(listResult: .failure(MockImportRepository.Failure.simulated))
        let vm = ImportHistoryViewModel(repository: repo)
        await vm.load()
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - Multiple loads

    func testSecondLoadReplacesJobs() async {
        let repo = MockImportRepository()
        await repo.set(listResult: .success([.fixture(id: "first")]))
        let vm = ImportHistoryViewModel(repository: repo)
        await vm.load()
        XCTAssertEqual(vm.jobs.first?.id, "first")

        await repo.set(listResult: .success([.fixture(id: "second"), .fixture(id: "third")]))
        await vm.load()
        XCTAssertEqual(vm.jobs.count, 2)
        XCTAssertEqual(vm.jobs.first?.id, "second")
    }

    // MARK: - EntityType on job rows

    func testJobEntityTypeIsPreserved() async {
        let repo = MockImportRepository()
        let job = ImportJob.fixture(id: "inv", entityType: .inventory)
        await repo.set(listResult: .success([job]))
        let vm = ImportHistoryViewModel(repository: repo)
        await vm.load()
        XCTAssertEqual(vm.jobs.first?.entityType, .inventory)
    }

    func testJobStatusIsPreserved() async {
        let repo = MockImportRepository()
        let job = ImportJob.fixture(status: .failed)
        await repo.set(listResult: .success([job]))
        let vm = ImportHistoryViewModel(repository: repo)
        await vm.load()
        XCTAssertEqual(vm.jobs.first?.status, .failed)
    }

    // MARK: - §48.4 Rollback

    func testInitiallyNotRollingBack() {
        let vm = ImportHistoryViewModel(repository: MockImportRepository())
        XCTAssertFalse(vm.isRollingBack)
    }

    func testInitiallyNoRollbackResult() {
        let vm = ImportHistoryViewModel(repository: MockImportRepository())
        XCTAssertNil(vm.rollbackResult)
    }

    func testRollback_success_setsSuccessResult() async {
        let repo = MockImportRepository()
        let job = ImportJob.completedWithRollback()
        await repo.set(listResult: .success([job]))
        let vm = ImportHistoryViewModel(repository: repo)
        await vm.load()

        await vm.rollback(job: job)

        if case .success(let msg) = vm.rollbackResult {
            XCTAssertFalse(msg.isEmpty)
        } else {
            XCTFail("Expected .success rollback result")
        }
    }

    func testRollback_success_callsRepositoryOnce() async {
        let repo = MockImportRepository()
        let job = ImportJob.completedWithRollback()
        await repo.set(listResult: .success([job]))
        let vm = ImportHistoryViewModel(repository: repo)
        await vm.load()

        await vm.rollback(job: job)

        let count = await repo.rollbackCallCount
        XCTAssertEqual(count, 1)
    }

    func testRollback_success_reloadsJobs() async {
        let repo = MockImportRepository()
        let job = ImportJob.completedWithRollback()
        await repo.set(listResult: .success([job]))
        let vm = ImportHistoryViewModel(repository: repo)
        await vm.load()

        // After rollback the server would return rolled-back status
        let rolledBack = ImportJob.fixture(id: "job-rb", status: .rolledBack)
        await repo.set(listResult: .success([rolledBack]))

        await vm.rollback(job: job)

        XCTAssertEqual(vm.jobs.first?.status, .rolledBack)
    }

    func testRollback_failure_setsFailureResult() async {
        let repo = MockImportRepository()
        let job = ImportJob.completedWithRollback()
        await repo.set(listResult: .success([job]))
        await repo.set(rollbackResult: .failure(MockImportRepository.Failure.simulated))
        let vm = ImportHistoryViewModel(repository: repo)
        await vm.load()

        await vm.rollback(job: job)

        if case .failure(let msg) = vm.rollbackResult {
            XCTAssertFalse(msg.isEmpty)
        } else {
            XCTFail("Expected .failure rollback result")
        }
    }

    func testRollback_nonRollbackableJob_doesNothing() async {
        let repo = MockImportRepository()
        let job = ImportJob.fixture(status: .failed) // canRollback = false
        let vm = ImportHistoryViewModel(repository: repo)

        await vm.rollback(job: job)

        let count = await repo.rollbackCallCount
        XCTAssertEqual(count, 0)
        XCTAssertNil(vm.rollbackResult)
    }

    func testRollback_notRollingBackAfterCompletion() async {
        let repo = MockImportRepository()
        let job = ImportJob.completedWithRollback()
        await repo.set(listResult: .success([job]))
        let vm = ImportHistoryViewModel(repository: repo)
        await vm.load()

        await vm.rollback(job: job)

        XCTAssertFalse(vm.isRollingBack)
    }

    func testClearRollbackResult_nilsResult() async {
        let repo = MockImportRepository()
        let job = ImportJob.completedWithRollback()
        await repo.set(listResult: .success([job]))
        let vm = ImportHistoryViewModel(repository: repo)
        await vm.load()
        await vm.rollback(job: job)
        XCTAssertNotNil(vm.rollbackResult)

        vm.clearRollbackResult()

        XCTAssertNil(vm.rollbackResult)
    }
}

// MARK: - MockImportRepository helpers

extension MockImportRepository {
    func set(listResult: Result<[ImportJob], Error>) {
        self.listResult = listResult
    }
    func set(rollbackResult: Result<RollbackImportResponse, Error>) {
        self.rollbackResult = rollbackResult
    }
}
