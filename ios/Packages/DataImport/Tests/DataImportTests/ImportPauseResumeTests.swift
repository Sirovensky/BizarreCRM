import XCTest
@testable import DataImport

/// §48.3 Pause / resume / cancel + §48.2 error report export.
@MainActor
final class ImportPauseResumeTests: XCTestCase {

    // MARK: - Helpers

    private func makeVM(repo: MockImportRepository) -> ImportWizardViewModel {
        ImportWizardViewModel(repository: repo)
    }

    private func vmWithRunningJob(repo: MockImportRepository) -> ImportWizardViewModel {
        let vm = makeVM(repo: repo)
        // Inject a running job directly
        vm.jobId = "job-1"
        vm.job = ImportJob.fixture(status: .running)
        return vm
    }

    private func vmWithPausedJob(repo: MockImportRepository) -> ImportWizardViewModel {
        let vm = makeVM(repo: repo)
        vm.jobId = "job-1"
        vm.job = ImportJob.fixture(status: .paused)
        return vm
    }

    // MARK: - §48.3 Pause

    func testPauseRunningJob() async throws {
        let repo = MockImportRepository()
        repo.pauseResult = .success(.fixture(status: .paused))
        let vm = vmWithRunningJob(repo: repo)

        await vm.pauseImport()

        let count = await repo.pauseCallCount
        XCTAssertEqual(count, 1, "pauseJob should be called once")
        XCTAssertEqual(vm.job?.status, .paused, "Job status should become paused")
        XCTAssertFalse(vm.isPausing, "isPausing should be false after completion")
    }

    func testPauseNonRunningJobIsNoop() async throws {
        let repo = MockImportRepository()
        let vm = makeVM(repo: repo)
        // No job set — noop
        vm.job = ImportJob.fixture(status: .completed)
        vm.jobId = "job-1"

        await vm.pauseImport()

        let count = await repo.pauseCallCount
        XCTAssertEqual(count, 0, "pauseJob should NOT be called when status is not running")
    }

    func testPauseError_doesNotCrash() async throws {
        let repo = MockImportRepository()
        repo.pauseResult = .failure(MockImportRepository.Failure.simulated)
        let vm = vmWithRunningJob(repo: repo)

        await vm.pauseImport()

        XCTAssertFalse(vm.isPausing, "isPausing resets even on failure")
        // Job status should remain running (unchanged on failure)
        XCTAssertEqual(vm.job?.status, .running)
    }

    // MARK: - §48.3 Resume

    func testResumePausedJob() async throws {
        let repo = MockImportRepository()
        repo.resumeResult = .success(.fixture(status: .running))
        let vm = vmWithPausedJob(repo: repo)

        await vm.resumeImport()

        let count = await repo.resumeCallCount
        XCTAssertEqual(count, 1)
        XCTAssertEqual(vm.job?.status, .running)
        XCTAssertFalse(vm.isResuming)
    }

    func testResumeNonPausedJobIsNoop() async throws {
        let repo = MockImportRepository()
        let vm = vmWithRunningJob(repo: repo)  // running, not paused

        await vm.resumeImport()

        let count = await repo.resumeCallCount
        XCTAssertEqual(count, 0)
    }

    func testResumeError_doesNotCrash() async throws {
        let repo = MockImportRepository()
        repo.resumeResult = .failure(MockImportRepository.Failure.simulated)
        let vm = vmWithPausedJob(repo: repo)

        await vm.resumeImport()

        XCTAssertFalse(vm.isResuming)
        XCTAssertEqual(vm.job?.status, .paused)  // unchanged on failure
    }

    // MARK: - §48.3 Cancel

    func testCancelResetsWizard() async throws {
        let repo = MockImportRepository()
        repo.cancelResult = .success(.init(message: "Cancelled"))
        let vm = vmWithRunningJob(repo: repo)

        await vm.cancelImport()

        let count = await repo.cancelCallCount
        XCTAssertEqual(count, 1)
        // After cancel, wizard resets
        XCTAssertNil(vm.jobId)
        XCTAssertNil(vm.job)
        XCTAssertFalse(vm.isCancelling)
    }

    func testCancelWithNoJobIdIsNoop() async throws {
        let repo = MockImportRepository()
        let vm = makeVM(repo: repo)

        await vm.cancelImport()

        let count = await repo.cancelCallCount
        XCTAssertEqual(count, 0)
    }

    // MARK: - §48.2 Error report export

    func testExportErrorsFetchesURL() async throws {
        let repo = MockImportRepository()
        let expectedURL = URL(string: "https://example.com/errors.csv")!
        repo.exportErrorsResult = .success(expectedURL)
        let vm = makeVM(repo: repo)
        vm.jobId = "job-1"

        await vm.exportErrors()

        let count = await repo.exportErrorsCallCount
        XCTAssertEqual(count, 1)
        XCTAssertEqual(vm.errorExportURL, expectedURL)
        XCTAssertFalse(vm.isExportingErrors)
    }

    func testExportErrorsNoJobIdIsNoop() async throws {
        let repo = MockImportRepository()
        let vm = makeVM(repo: repo)
        // No jobId

        await vm.exportErrors()

        let count = await repo.exportErrorsCallCount
        XCTAssertEqual(count, 0)
        XCTAssertNil(vm.errorExportURL)
    }

    func testExportErrorsFailureClearsURL() async throws {
        let repo = MockImportRepository()
        repo.exportErrorsResult = .failure(MockImportRepository.Failure.simulated)
        let vm = makeVM(repo: repo)
        vm.jobId = "job-1"

        await vm.exportErrors()

        XCTAssertNil(vm.errorExportURL)
        XCTAssertFalse(vm.isExportingErrors)
    }

    // MARK: - ImportStatus helpers

    func testImportStatusIsRunning() {
        XCTAssertTrue(ImportStatus.running.isRunning)
        XCTAssertFalse(ImportStatus.paused.isRunning)
        XCTAssertFalse(ImportStatus.completed.isRunning)
    }

    func testImportStatusIsPaused() {
        XCTAssertTrue(ImportStatus.paused.isPaused)
        XCTAssertFalse(ImportStatus.running.isPaused)
    }
}
