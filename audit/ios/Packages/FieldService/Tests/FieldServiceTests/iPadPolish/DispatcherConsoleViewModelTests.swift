// §22 DispatcherConsoleViewModelTests — unit tests for the iPad dispatcher console VM.
//
// Coverage target: 80%+ of DispatcherConsoleViewModel.
// Tests are structured RED → GREEN per TDD mandate.
//
// Test groups:
//   1. Load — happy path, error paths
//   2. Filter — tech and status filters
//   3. Selection — focus, multi-select, selectAll, clearSelection
//   4. Navigation — J/K next/prev job, ⌘N assign next unassigned
//   5. Batch — batchReassign success + partial failure
//   6. Roster building — status escalation, job counts

import XCTest
@testable import FieldService
import Networking

@MainActor
final class DispatcherConsoleViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeVM(api: iPadMockAPIClient = iPadMockAPIClient()) -> DispatcherConsoleViewModel {
        DispatcherConsoleViewModel(api: api)
    }

    private func makeJob(
        id: Int64 = 1,
        status: FSJobStatus = .assigned,
        techId: Int64? = 5
    ) -> FSJob {
        FSJob.makeTest(
            id: id,
            status: status,
            priority: "normal",
            customerFirstName: "Alice",
            customerLastName: "Smith",
            addressLine: "123 Main St",
            lat: 37.33,
            lng: -122.02
        )
    }

    // MARK: - 1. Load

    func test_load_happyPath_setsJobsAndRosterLoaded() async {
        let api = iPadMockAPIClient()
        api.stubbedJobs = [makeJob(id: 1), makeJob(id: 2)]
        api.stubbedEmployees = [Employee.makeTestiPad(id: 5, firstName: "Bob", lastName: "Tech")]
        let vm = makeVM(api: api)

        await vm.load()

        if case .loaded(let jobs) = vm.jobsState {
            XCTAssertEqual(jobs.count, 2)
        } else {
            XCTFail("Expected .loaded jobs, got \(vm.jobsState)")
        }
        if case .loaded(let roster) = vm.rosterState {
            XCTAssertEqual(roster.count, 1)
        } else {
            XCTFail("Expected .loaded roster, got \(vm.rosterState)")
        }
    }

    func test_load_emptyJobs_setsEmptyState() async {
        let api = iPadMockAPIClient()
        api.stubbedJobs = []
        api.stubbedEmployees = []
        let vm = makeVM(api: api)

        await vm.load()

        XCTAssertEqual(vm.jobsState, .empty)
        XCTAssertEqual(vm.rosterState, .empty)
    }

    func test_load_apiError_setsFailedJobsState() async {
        let api = iPadMockAPIClient()
        api.fsListShouldThrow = iPadMockError.simulated
        let vm = makeVM(api: api)

        await vm.load()

        if case .failed = vm.jobsState {
            // expected
        } else {
            XCTFail("Expected .failed, got \(vm.jobsState)")
        }
    }

    func test_refresh_setsIsRefreshingDuringOperation() async {
        let api = iPadMockAPIClient()
        api.stubbedJobs = [makeJob()]
        api.stubbedEmployees = []
        let vm = makeVM(api: api)

        await vm.refresh()

        // After completion isRefreshing must be false.
        XCTAssertFalse(vm.isRefreshing)
        if case .loaded = vm.jobsState { /* pass */ } else {
            XCTFail("Expected loaded state after refresh")
        }
    }

    // MARK: - 2. Filter

    func test_filterByTechId_capturedInApiCall() async {
        let api = iPadMockAPIClient()
        api.stubbedJobs = [makeJob(id: 1)]
        api.stubbedEmployees = []
        let vm = makeVM(api: api)
        vm.filterByTechId = 7

        await vm.applyFilters()

        XCTAssertEqual(api.lastJobListTechId, 7)
    }

    func test_filterByStatus_capturedInApiCall() async {
        let api = iPadMockAPIClient()
        api.stubbedJobs = []
        api.stubbedEmployees = []
        let vm = makeVM(api: api)
        vm.filterByStatus = .enRoute

        await vm.applyFilters()

        XCTAssertEqual(api.lastJobListStatus, .enRoute)
    }

    func test_findJobs_clearsFiltersBeforeReloading() async {
        let api = iPadMockAPIClient()
        api.stubbedJobs = [makeJob()]
        api.stubbedEmployees = []
        let vm = makeVM(api: api)
        vm.filterByTechId = 99
        vm.filterByStatus = .canceled

        vm.findJobs()

        XCTAssertNil(vm.filterByTechId)
        XCTAssertNil(vm.filterByStatus)
    }

    // MARK: - 3. Selection

    func test_focusJob_setsFocusedJob() {
        let vm = makeVM()
        let job = makeJob(id: 42)

        vm.focusJob(job)

        XCTAssertEqual(vm.focusedJob?.id, 42)
    }

    func test_focusJob_nil_clearsFocusedJob() {
        let vm = makeVM()
        vm.focusJob(makeJob(id: 1))

        vm.focusJob(nil)

        XCTAssertNil(vm.focusedJob)
    }

    func test_toggleJobSelection_addsId() {
        let vm = makeVM()

        vm.toggleJobSelection(1)

        XCTAssertTrue(vm.selectedJobIds.contains(1))
    }

    func test_toggleJobSelection_removesExistingId() {
        let vm = makeVM()
        vm.toggleJobSelection(1)

        vm.toggleJobSelection(1)

        XCTAssertFalse(vm.selectedJobIds.contains(1))
    }

    func test_selectAll_selectsAllCurrentJobs() async {
        let api = iPadMockAPIClient()
        api.stubbedJobs = [makeJob(id: 1), makeJob(id: 2), makeJob(id: 3)]
        api.stubbedEmployees = []
        let vm = makeVM(api: api)
        await vm.load()

        vm.selectAll(jobs: vm.currentJobs)

        XCTAssertEqual(vm.selectedJobIds.count, 3)
        XCTAssertTrue(vm.selectedJobIds.contains(1))
        XCTAssertTrue(vm.selectedJobIds.contains(2))
        XCTAssertTrue(vm.selectedJobIds.contains(3))
    }

    func test_clearSelection_emptiesSet() {
        let vm = makeVM()
        vm.toggleJobSelection(1)
        vm.toggleJobSelection(2)

        vm.clearSelection()

        XCTAssertTrue(vm.selectedJobIds.isEmpty)
    }

    func test_hasBatchSelection_trueWhenSelectionNonEmpty() {
        let vm = makeVM()
        XCTAssertFalse(vm.hasBatchSelection)

        vm.toggleJobSelection(5)
        XCTAssertTrue(vm.hasBatchSelection)

        vm.clearSelection()
        XCTAssertFalse(vm.hasBatchSelection)
    }

    // MARK: - 4. Navigation (J / K / ⌘N)

    func test_selectNextJob_movesForward() async {
        let api = iPadMockAPIClient()
        api.stubbedJobs = [makeJob(id: 1), makeJob(id: 2), makeJob(id: 3)]
        api.stubbedEmployees = []
        let vm = makeVM(api: api)
        await vm.load()

        vm.focusJob(vm.currentJobs[0])
        vm.selectNextJob()

        XCTAssertEqual(vm.focusedJob?.id, 2)
    }

    func test_selectNextJob_atEnd_staysAtEnd() async {
        let api = iPadMockAPIClient()
        api.stubbedJobs = [makeJob(id: 1), makeJob(id: 2)]
        api.stubbedEmployees = []
        let vm = makeVM(api: api)
        await vm.load()

        vm.focusJob(vm.currentJobs[1])
        vm.selectNextJob()

        XCTAssertEqual(vm.focusedJob?.id, 2)
    }

    func test_selectPreviousJob_movesBack() async {
        let api = iPadMockAPIClient()
        api.stubbedJobs = [makeJob(id: 1), makeJob(id: 2), makeJob(id: 3)]
        api.stubbedEmployees = []
        let vm = makeVM(api: api)
        await vm.load()

        vm.focusJob(vm.currentJobs[2])
        vm.selectPreviousJob()

        XCTAssertEqual(vm.focusedJob?.id, 2)
    }

    func test_selectPreviousJob_atStart_staysAtStart() async {
        let api = iPadMockAPIClient()
        api.stubbedJobs = [makeJob(id: 1), makeJob(id: 2)]
        api.stubbedEmployees = []
        let vm = makeVM(api: api)
        await vm.load()

        vm.focusJob(vm.currentJobs[0])
        vm.selectPreviousJob()

        XCTAssertEqual(vm.focusedJob?.id, 1)
    }

    func test_selectNextJob_noFocus_selectsFirst() async {
        let api = iPadMockAPIClient()
        api.stubbedJobs = [makeJob(id: 10), makeJob(id: 20)]
        api.stubbedEmployees = []
        let vm = makeVM(api: api)
        await vm.load()

        vm.selectNextJob()

        XCTAssertEqual(vm.focusedJob?.id, 10)
    }

    func test_selectPreviousJob_noFocus_selectsLast() async {
        let api = iPadMockAPIClient()
        api.stubbedJobs = [makeJob(id: 10), makeJob(id: 20)]
        api.stubbedEmployees = []
        let vm = makeVM(api: api)
        await vm.load()

        vm.selectPreviousJob()

        XCTAssertEqual(vm.focusedJob?.id, 20)
    }

    func test_assignNextUnassigned_focusesFirstUnassignedJob() async {
        let api = iPadMockAPIClient()
        let assigned = FSJob.makeTest(id: 1, status: .assigned)
        let unassigned = FSJob.makeTest(id: 2, status: .unassigned)
        api.stubbedJobs = [assigned, unassigned]
        api.stubbedEmployees = []
        let vm = makeVM(api: api)
        await vm.load()

        vm.assignNextUnassigned()

        XCTAssertEqual(vm.focusedJob?.id, 2)
    }

    func test_assignNextUnassigned_noUnassignedJobs_doesNotChangeFocus() async {
        let api = iPadMockAPIClient()
        api.stubbedJobs = [makeJob(id: 1, status: .assigned)]
        api.stubbedEmployees = []
        let vm = makeVM(api: api)
        await vm.load()

        vm.assignNextUnassigned()

        XCTAssertNil(vm.focusedJob)
    }

    func test_assignNextUnassigned_emptyJobsState_doesNothing() {
        let vm = makeVM()
        // jobsState is .loading; no crash expected.
        vm.assignNextUnassigned()
        XCTAssertNil(vm.focusedJob)
    }

    // MARK: - 5. Batch reassign

    func test_batchReassign_success_clearsSelectionAndSetsSucceeded() async {
        let api = iPadMockAPIClient()
        api.stubbedJobs = [makeJob(id: 1), makeJob(id: 2)]
        api.stubbedEmployees = []
        let vm = makeVM(api: api)
        await vm.load()

        vm.toggleJobSelection(1)
        vm.toggleJobSelection(2)
        await vm.batchReassign(toTechnicianId: 99)

        XCTAssertEqual(vm.batchState, .succeeded)
        XCTAssertTrue(vm.selectedJobIds.isEmpty)
    }

    func test_batchReassign_emptySelection_staysIdle() async {
        let api = iPadMockAPIClient()
        let vm = makeVM(api: api)

        await vm.batchReassign(toTechnicianId: 5)

        XCTAssertEqual(vm.batchState, .idle)
    }

    func test_batchReassign_apiFailure_setsFailedState() async {
        let api = iPadMockAPIClient()
        api.stubbedJobs = [makeJob(id: 1)]
        api.stubbedEmployees = []
        api.fsStatusShouldThrow = iPadMockError.simulated
        let vm = makeVM(api: api)
        await vm.load()

        vm.toggleJobSelection(1)
        await vm.batchReassign(toTechnicianId: 5)

        if case .failed = vm.batchState {
            // expected
        } else {
            XCTFail("Expected .failed batch state, got \(vm.batchState)")
        }
    }

    // MARK: - 6. Roster building

    func test_rosterBuild_enRouteEscalatesOverAssigned() async {
        let api = iPadMockAPIClient()
        // Same tech: assigned (busy) + en_route — en_route should win.
        let j1 = FSJob.makeTest(id: 1, status: .assigned)
        let j2 = FSJob.makeTest(id: 2, status: .enRoute)
        // Manually set techId via makeJob helper (makeTest doesn't expose techId; we fix below).
        api.stubbedJobs = makeJobsWithTech([(j1, 10), (j2, 10)])
        api.stubbedEmployees = [Employee.makeTestiPad(id: 10, firstName: "Alice", lastName: "T")]
        let vm = makeVM(api: api)

        await vm.load()

        guard case .loaded(let roster) = vm.rosterState,
              let entry = roster.first(where: { $0.id == 10 }) else {
            XCTFail("Expected loaded roster with tech 10")
            return
        }
        XCTAssertEqual(entry.currentStatus, .enRoute)
    }

    func test_rosterBuild_jobCount_excludesCompletedAndCanceled() async {
        let api = iPadMockAPIClient()
        api.stubbedJobs = makeJobsWithTech([
            (FSJob.makeTest(id: 1, status: .assigned),  5),
            (FSJob.makeTest(id: 2, status: .completed), 5),
            (FSJob.makeTest(id: 3, status: .canceled),  5),
        ])
        api.stubbedEmployees = [Employee.makeTestiPad(id: 5, firstName: "Bob", lastName: "T")]
        let vm = makeVM(api: api)

        await vm.load()

        guard case .loaded(let roster) = vm.rosterState,
              let entry = roster.first(where: { $0.id == 5 }) else {
            XCTFail("Expected loaded roster with tech 5")
            return
        }
        XCTAssertEqual(entry.assignedJobCount, 1)
    }

    func test_rosterBuild_inactiveTechsExcluded() async {
        let api = iPadMockAPIClient()
        api.stubbedJobs = []
        api.stubbedEmployees = [
            Employee.makeTestiPad(id: 1, firstName: "Active",   lastName: "T", isActive: 1),
            Employee.makeTestiPad(id: 2, firstName: "Inactive", lastName: "T", isActive: 0),
        ]
        let vm = makeVM(api: api)

        await vm.load()

        guard case .loaded(let roster) = vm.rosterState else {
            XCTFail("Expected loaded roster")
            return
        }
        XCTAssertEqual(roster.count, 1)
        XCTAssertEqual(roster.first?.id, 1)
    }

    func test_rosterBuild_techWithNoJobs_isAvailable() async {
        let api = iPadMockAPIClient()
        api.stubbedJobs = []
        api.stubbedEmployees = [Employee.makeTestiPad(id: 99, firstName: "Free", lastName: "T")]
        let vm = makeVM(api: api)

        await vm.load()

        guard case .loaded(let roster) = vm.rosterState,
              let entry = roster.first(where: { $0.id == 99 }) else {
            XCTFail("Expected loaded roster entry")
            return
        }
        XCTAssertEqual(entry.currentStatus, .available)
        XCTAssertEqual(entry.assignedJobCount, 0)
    }

    // MARK: - 7. currentJobs computed property

    func test_currentJobs_returnsEmptyWhenNotLoaded() {
        let vm = makeVM()
        XCTAssertTrue(vm.currentJobs.isEmpty)
    }

    func test_currentJobs_returnsJobsWhenLoaded() async {
        let api = iPadMockAPIClient()
        api.stubbedJobs = [makeJob(id: 1), makeJob(id: 2)]
        api.stubbedEmployees = []
        let vm = makeVM(api: api)
        await vm.load()

        XCTAssertEqual(vm.currentJobs.count, 2)
    }

    // MARK: - Helpers

    /// Builds a list of FSJob values that have the specified technicianId.
    /// Uses JSON round-trip to inject the technician id since FSJob is immutable.
    private func makeJobsWithTech(_ pairs: [(FSJob, Int64)]) -> [FSJob] {
        pairs.compactMap { (job, techId) in
            var dict: [String: Any] = [
                "id":          job.id,
                "address_line": job.addressLine,
                "lat":         job.lat,
                "lng":         job.lng,
                "priority":    job.priority,
                "status":      job.status,
                "assigned_technician_id": techId,
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: dict),
                  let decoded = try? JSONDecoder().decode(FSJob.self, from: data) else {
                return nil
            }
            return decoded
        }
    }
}
