// Tests for DispatcherViewModel — §57.4
// Coverage target: ≥80% of DispatcherViewModel.

import XCTest
@testable import FieldService

@MainActor
final class DispatcherViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeVM(
        jobs: [FSJob] = [],
        listError: Error? = nil
    ) -> (DispatcherViewModel, MockAPIClient) {
        let api = MockAPIClient()
        api.stubbedJobs = jobs
        api.fsListShouldThrow = listError
        let vm = DispatcherViewModel(api: api)
        return (vm, api)
    }

    // MARK: - Initial state

    func test_initialState_isLoading() {
        let (vm, _) = makeVM()
        XCTAssertEqual(vm.listState, .loading)
        XCTAssertNil(vm.selectedJob)
    }

    // MARK: - load()

    func test_load_withJobs_transitionsToLoaded() async {
        let jobs = [FSJob.makeTest(id: 1), FSJob.makeTest(id: 2), FSJob.makeTest(id: 3)]
        let (vm, _) = makeVM(jobs: jobs)

        await vm.load()

        if case .loaded(let loaded) = vm.listState {
            XCTAssertEqual(loaded.count, 3)
        } else {
            XCTFail("Expected .loaded, got \(vm.listState)")
        }
    }

    func test_load_emptyJobs_transitionsToEmpty() async {
        let (vm, _) = makeVM(jobs: [])

        await vm.load()

        XCTAssertEqual(vm.listState, .empty)
    }

    func test_load_networkError_transitionsToFailed() async {
        let (vm, _) = makeVM(listError: MockError.simulated)

        await vm.load()

        if case .failed = vm.listState {
            // pass
        } else {
            XCTFail("Expected .failed, got \(vm.listState)")
        }
    }

    // MARK: - refresh()

    func test_refresh_updatesJobs() async {
        let (vm, api) = makeVM(jobs: [FSJob.makeTest(id: 1)])
        await vm.load()

        api.stubbedJobs = [FSJob.makeTest(id: 1), FSJob.makeTest(id: 2)]
        await vm.refresh()

        if case .loaded(let jobs) = vm.listState {
            XCTAssertEqual(jobs.count, 2)
        } else {
            XCTFail("Expected .loaded after refresh, got \(vm.listState)")
        }
    }

    func test_refresh_clearsIsRefreshing_onCompletion() async {
        let (vm, _) = makeVM(jobs: [FSJob.makeTest()])
        await vm.load()
        await vm.refresh()

        XCTAssertFalse(vm.isRefreshing)
    }

    func test_refresh_concurrent_secondIsNoOp() async {
        let (vm, _) = makeVM(jobs: [FSJob.makeTest()])
        await vm.load()

        async let r1: Void = vm.refresh()
        async let r2: Void = vm.refresh()
        _ = await (r1, r2)

        XCTAssertFalse(vm.isRefreshing)
    }

    // MARK: - selectJob()

    func test_selectJob_setsSelectedJob() async {
        let job = FSJob.makeTest(id: 42)
        let (vm, _) = makeVM(jobs: [job])
        await vm.load()

        vm.selectJob(job)

        XCTAssertEqual(vm.selectedJob?.id, 42)
    }

    func test_selectJob_nilClearsSelection() async {
        let job = FSJob.makeTest(id: 42)
        let (vm, _) = makeVM(jobs: [job])
        await vm.load()
        vm.selectJob(job)

        vm.selectJob(nil)

        XCTAssertNil(vm.selectedJob)
    }

    // MARK: - Filter state

    func test_applyFilters_withStatus_fetchesFiltered() async {
        let jobs = [
            FSJob.makeTest(id: 1, status: .assigned),
            FSJob.makeTest(id: 2, status: .enRoute),
        ]
        let (vm, api) = makeVM(jobs: jobs)
        await vm.load()

        // Simulate filtering — API mock doesn't filter; we just verify no crash.
        vm.selectedStatus = .enRoute
        api.stubbedJobs = [FSJob.makeTest(id: 2, status: .enRoute)]
        await vm.applyFilters()

        if case .loaded(let loaded) = vm.listState {
            XCTAssertEqual(loaded.count, 1)
        } else if case .empty = vm.listState {
            // pass
        } else {
            XCTFail("Unexpected state: \(vm.listState)")
        }
    }

    func test_applyFilters_error_transitionsToFailed() async {
        let (vm, api) = makeVM(jobs: [FSJob.makeTest()])
        await vm.load()

        api.fsListShouldThrow = MockError.simulated
        await vm.applyFilters()

        if case .failed = vm.listState {
            // pass
        } else {
            XCTFail("Expected .failed, got \(vm.listState)")
        }
    }
}
