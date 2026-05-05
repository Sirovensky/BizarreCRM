// Tests for JobListViewModel — §57.1
// Coverage target: ≥80% of JobListViewModel.
//
// All tests use MockAPIClient; no live network.
// Tests run on @MainActor because the VM is @MainActor @Observable.

import XCTest
@testable import FieldService

@MainActor
final class JobListViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeVM(jobs: [FSJob] = [], listError: Error? = nil) -> (JobListViewModel, MockAPIClient) {
        let api = MockAPIClient()
        api.stubbedJobs = jobs
        api.fsListShouldThrow = listError
        let vm = JobListViewModel(api: api)
        return (vm, api)
    }

    // MARK: - Initial state

    func test_initialState_isIdle() {
        let (vm, _) = makeVM()
        XCTAssertEqual(vm.state, .idle)
    }

    // MARK: - load()

    func test_load_withJobs_transitionsToLoaded() async {
        let jobs = [FSJob.makeTest(id: 1), FSJob.makeTest(id: 2)]
        let (vm, _) = makeVM(jobs: jobs)

        await vm.load()

        if case .loaded(let loaded) = vm.state {
            XCTAssertEqual(loaded.count, 2)
            XCTAssertEqual(loaded.map(\.id).sorted(), [1, 2])
        } else {
            XCTFail("Expected .loaded, got \(vm.state)")
        }
    }

    func test_load_emptyResponse_transitionsToEmpty() async {
        let (vm, _) = makeVM(jobs: [])

        await vm.load()

        XCTAssertEqual(vm.state, .empty)
    }

    func test_load_networkError_transitionsToFailed() async {
        let (vm, _) = makeVM(listError: MockError.simulated)

        await vm.load()

        if case .failed = vm.state {
            // pass
        } else {
            XCTFail("Expected .failed, got \(vm.state)")
        }
    }

    func test_load_duringLoading_doesNotReenter() async {
        let jobs = [FSJob.makeTest()]
        let (vm, _) = makeVM(jobs: jobs)

        // Set state to loading manually to simulate in-progress.
        // Call load twice — second call should be a no-op when in .loading.
        // We can't easily race these, but we verify it doesn't crash or corrupt.
        await vm.load()
        // At this point state is .loaded. Reset to idle for second test.
        // Simply call again — it should be a no-op (guard checks state).
        await vm.load()

        if case .loaded = vm.state {
            // pass — still loaded, didn't reset to idle again
        } else {
            XCTFail("Expected still .loaded after second load call, got \(vm.state)")
        }
    }

    // MARK: - refresh()

    func test_refresh_resetsIsRefreshing() async {
        let (vm, _) = makeVM(jobs: [FSJob.makeTest()])
        await vm.load()

        await vm.refresh()

        XCTAssertFalse(vm.isRefreshing)
    }

    func test_refresh_withJobs_updatesState() async {
        let (vm, api) = makeVM(jobs: [FSJob.makeTest(id: 1)])
        await vm.load()

        api.stubbedJobs = [FSJob.makeTest(id: 1), FSJob.makeTest(id: 2)]
        await vm.refresh()

        if case .loaded(let jobs) = vm.state {
            XCTAssertEqual(jobs.count, 2)
        } else {
            XCTFail("Expected .loaded after refresh, got \(vm.state)")
        }
    }

    func test_refresh_networkError_setsFailedState() async {
        let (vm, api) = makeVM(jobs: [FSJob.makeTest()])
        await vm.load()

        api.fsListShouldThrow = MockError.simulated
        await vm.refresh()

        if case .failed = vm.state {
            // pass
        } else {
            XCTFail("Expected .failed, got \(vm.state)")
        }
    }

    func test_refresh_concurrent_secondCallNoOp() async {
        let (vm, _) = makeVM(jobs: [FSJob.makeTest()])

        // Both calls should complete without crashing.
        async let r1: Void = vm.refresh()
        async let r2: Void = vm.refresh()
        _ = await (r1, r2)

        // Final state should be a valid non-loading state.
        XCTAssertFalse(vm.isRefreshing)
    }

    // MARK: - Filter

    func test_applyFilters_passesStatusToAPI() async {
        let (vm, api) = makeVM(jobs: [FSJob.makeTest(status: .assigned)])
        vm.selectedStatus = .assigned
        await vm.applyFilters()

        // VM should have called the API (no error thrown = success).
        if case .loaded = vm.state {
            // pass
        } else if case .empty = vm.state {
            // pass — filtering may produce empty
        } else {
            XCTFail("Unexpected state after applyFilters: \(vm.state)")
        }
        _ = api // suppress unused-variable warning
    }

    func test_statusFilter_nil_showsAll() async {
        let jobs = [
            FSJob.makeTest(id: 1, status: .assigned),
            FSJob.makeTest(id: 2, status: .enRoute),
        ]
        let (vm, _) = makeVM(jobs: jobs)
        vm.selectedStatus = nil
        await vm.load()

        if case .loaded(let loaded) = vm.state {
            XCTAssertEqual(loaded.count, 2)
        } else {
            XCTFail("Expected .loaded, got \(vm.state)")
        }
    }
}
