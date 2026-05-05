import XCTest
@testable import Timeclock
@testable import Networking

// MARK: - ApprovalActionViewModelTests
//
// Covers §14 Task 2: ApprovalActionViewModel approve/reject state machine.
// All tests are @MainActor because the VM is @MainActor @Observable.

@MainActor
final class ApprovalActionViewModelTests: XCTestCase {

    // MARK: - Approve: success path

    func test_approve_setsApprovedState_onSuccess() async {
        let entry = makeEntry(id: 10)
        let api = StubApprovalAPI(editResult: entry)
        let vm = ApprovalActionViewModel(entry: entry, api: api)

        await vm.approve()

        XCTAssertEqual(vm.actionState, .approved)
    }

    func test_approve_sendsApprovedReasonPrefix() async {
        let entry = makeEntry(id: 11)
        let api = StubApprovalAPI(editResult: entry)
        let vm = ApprovalActionViewModel(entry: entry, api: api)

        await vm.approve()

        XCTAssertTrue(
            api.lastReason?.hasPrefix(ApprovalReasonPrefix.approved) == true,
            "Reason must start with [\(ApprovalReasonPrefix.approved)]"
        )
    }

    func test_approve_appendsExtraNote_whenProvided() async {
        let entry = makeEntry(id: 12)
        let api = StubApprovalAPI(editResult: entry)
        let vm = ApprovalActionViewModel(entry: entry, api: api)

        await vm.approve(extraNote: "Confirmed with employee")

        XCTAssertEqual(api.lastReason, "\(ApprovalReasonPrefix.approved) Confirmed with employee")
    }

    func test_approve_setsFailedState_onError() async {
        let entry = makeEntry(id: 13)
        let api = StubApprovalAPI(editError: TestApprovalError.boom)
        let vm = ApprovalActionViewModel(entry: entry, api: api)

        await vm.approve()

        guard case .failed = vm.actionState else {
            XCTFail("Expected .failed, got \(vm.actionState)"); return
        }
    }

    func test_approve_doesNothing_whenAlreadyProcessing() async {
        let entry = makeEntry(id: 14)
        // Simulate processing by setting state manually via action
        let api = StubApprovalAPI(editResult: entry)
        let vm = ApprovalActionViewModel(entry: entry, api: api)
        // After first approve, state = .approved; second call should be ignored
        await vm.approve()
        XCTAssertEqual(vm.actionState, .approved)

        // Second call — should not call the API again
        api.resetCallCount()
        await vm.approve()
        XCTAssertEqual(api.editCallCount, 0, "Should not call API again after approved")
    }

    // MARK: - Reject: success path

    func test_reject_setsRejectedState_onSuccess() async {
        let entry = makeEntry(id: 20)
        let api = StubApprovalAPI(editResult: entry)
        let vm = ApprovalActionViewModel(entry: entry, api: api)
        vm.reason = "Time off not approved"

        await vm.reject()

        XCTAssertEqual(vm.actionState, .rejected)
    }

    func test_reject_sendsRejectedReasonPrefix() async {
        let entry = makeEntry(id: 21)
        let api = StubApprovalAPI(editResult: entry)
        let vm = ApprovalActionViewModel(entry: entry, api: api)
        vm.reason = "Clocked in twice by mistake"

        await vm.reject()

        XCTAssertTrue(
            api.lastReason?.hasPrefix(ApprovalReasonPrefix.rejected) == true,
            "Reason must start with \(ApprovalReasonPrefix.rejected)"
        )
    }

    func test_reject_appendsUserReason() async {
        let entry = makeEntry(id: 22)
        let api = StubApprovalAPI(editResult: entry)
        let vm = ApprovalActionViewModel(entry: entry, api: api)
        vm.reason = "Hours not matching"

        await vm.reject()

        XCTAssertEqual(api.lastReason, "\(ApprovalReasonPrefix.rejected) Hours not matching")
    }

    func test_reject_setsFailedState_whenReasonEmpty() async {
        let entry = makeEntry(id: 23)
        let api = StubApprovalAPI(editResult: entry)
        let vm = ApprovalActionViewModel(entry: entry, api: api)
        vm.reason = "   " // whitespace only

        await vm.reject()

        guard case let .failed(msg) = vm.actionState else {
            XCTFail("Expected .failed, got \(vm.actionState)"); return
        }
        XCTAssertFalse(msg.isEmpty)
        XCTAssertEqual(api.editCallCount, 0, "Should not call API when reason is empty")
    }

    func test_reject_setsFailedState_onAPIError() async {
        let entry = makeEntry(id: 24)
        let api = StubApprovalAPI(editError: TestApprovalError.boom)
        let vm = ApprovalActionViewModel(entry: entry, api: api)
        vm.reason = "Valid reason"

        await vm.reject()

        guard case .failed = vm.actionState else {
            XCTFail("Expected .failed, got \(vm.actionState)"); return
        }
    }

    // MARK: - canApprove / canReject validation

    func test_canApprove_trueInIdleState() {
        let entry = makeEntry(id: 30)
        let api = StubApprovalAPI(editResult: entry)
        let vm = ApprovalActionViewModel(entry: entry, api: api)
        XCTAssertTrue(vm.canApprove)
    }

    func test_canReject_falseWhenReasonEmpty() {
        let entry = makeEntry(id: 31)
        let api = StubApprovalAPI(editResult: entry)
        let vm = ApprovalActionViewModel(entry: entry, api: api)
        vm.reason = ""
        XCTAssertFalse(vm.canReject)
    }

    func test_canReject_trueWhenReasonNonEmpty() {
        let entry = makeEntry(id: 32)
        let api = StubApprovalAPI(editResult: entry)
        let vm = ApprovalActionViewModel(entry: entry, api: api)
        vm.reason = "Some reason"
        XCTAssertTrue(vm.canReject)
    }
}

// MARK: - PendingApprovalsViewModelTests

@MainActor
final class PendingApprovalsViewModelTests: XCTestCase {

    // MARK: - Load

    func test_load_groupsEntriesByEmployee() async {
        let entries = [
            makeEntry(id: 1, userId: 100),
            makeEntry(id: 2, userId: 100),
            makeEntry(id: 3, userId: 200)
        ]
        let api = StubApprovalAPI(entries: entries)
        let vm = PendingApprovalsViewModel(api: api)

        await vm.load()

        XCTAssertEqual(vm.loadState, .loaded)
        XCTAssertEqual(vm.groups.count, 2)
        let group100 = vm.groups.first(where: { $0.employeeId == 100 })
        XCTAssertEqual(group100?.entries.count, 2)
        let group200 = vm.groups.first(where: { $0.employeeId == 200 })
        XCTAssertEqual(group200?.entries.count, 1)
    }

    func test_load_allEntriesStartAsPending() async {
        let entries = [makeEntry(id: 1, userId: 10), makeEntry(id: 2, userId: 10)]
        let api = StubApprovalAPI(entries: entries)
        let vm = PendingApprovalsViewModel(api: api)

        await vm.load()

        let allPending = vm.groups.flatMap(\.entries).allSatisfy { $0.status == .pending }
        XCTAssertTrue(allPending, "All newly loaded entries must start as .pending")
    }

    func test_load_setsFailedState_onError() async {
        let api = StubApprovalAPI(listError: TestApprovalError.boom)
        let vm = PendingApprovalsViewModel(api: api)

        await vm.load()

        guard case .failed = vm.loadState else {
            XCTFail("Expected .failed"); return
        }
    }

    func test_load_emptyGroups_whenNoEntries() async {
        let api = StubApprovalAPI(entries: [])
        let vm = PendingApprovalsViewModel(api: api)

        await vm.load()

        XCTAssertTrue(vm.groups.isEmpty)
    }

    // MARK: - Approve single

    func test_approve_changesEntryStatus_toApproved() async {
        let entry = makeEntry(id: 5, userId: 50)
        let api = StubApprovalAPI(entries: [entry], editResult: entry)
        let vm = PendingApprovalsViewModel(api: api)
        await vm.load()

        await vm.approve(entry: entry)

        let status = vm.groups.first?.entries.first?.status
        XCTAssertEqual(status, .approved)
    }

    func test_approve_immutableUpdate_preservesOtherEntries() async {
        let e1 = makeEntry(id: 1, userId: 10)
        let e2 = makeEntry(id: 2, userId: 10)
        let api = StubApprovalAPI(entries: [e1, e2], editResult: e1)
        let vm = PendingApprovalsViewModel(api: api)
        await vm.load()

        await vm.approve(entry: e1)

        let group = vm.groups.first!
        XCTAssertEqual(group.entries.count, 2, "Entry count must not change after approve")
        XCTAssertEqual(group.entries.first(where: { $0.id == 2 })?.status, .pending)
    }

    // MARK: - Reject single

    func test_reject_changesEntryStatus_toRejected() async {
        let entry = makeEntry(id: 6, userId: 60)
        let api = StubApprovalAPI(entries: [entry], editResult: entry)
        let vm = PendingApprovalsViewModel(api: api)
        await vm.load()

        await vm.reject(entry: entry, reason: "Too many hours")

        let status = vm.groups.first?.entries.first?.status
        guard case let .rejected(reason) = status else {
            XCTFail("Expected .rejected, got \(String(describing: status))"); return
        }
        XCTAssertEqual(reason, "Too many hours")
    }

    func test_reject_doesNothing_whenReasonEmpty() async {
        let entry = makeEntry(id: 7, userId: 70)
        let api = StubApprovalAPI(entries: [entry], editResult: entry)
        let vm = PendingApprovalsViewModel(api: api)
        await vm.load()

        await vm.reject(entry: entry, reason: "  ")

        XCTAssertEqual(api.editCallCount, 0, "API should not be called with empty reason")
        XCTAssertEqual(vm.groups.first?.entries.first?.status, .pending)
    }

    // MARK: - Bulk approve

    func test_approveAll_setsAllEntriesApproved() async {
        let e1 = makeEntry(id: 1, userId: 11)
        let e2 = makeEntry(id: 2, userId: 11)
        let api = StubApprovalAPI(entries: [e1, e2], editResult: e1)
        let vm = PendingApprovalsViewModel(api: api)
        await vm.load()

        await vm.approveAll(employeeId: 11)

        XCTAssertEqual(vm.bulkState, .done)
        let allApproved = vm.groups.first?.entries.allSatisfy { $0.status == .approved } ?? false
        XCTAssertTrue(allApproved)
    }

    func test_approveAll_setBulkFailedState_onAPIError() async {
        let entry = makeEntry(id: 1, userId: 11)
        let api = StubApprovalAPI(entries: [entry], editError: TestApprovalError.boom)
        let vm = PendingApprovalsViewModel(api: api)
        await vm.load()

        await vm.approveAll(employeeId: 11)

        guard case .failed = vm.bulkState else {
            XCTFail("Expected .failed, got \(vm.bulkState)"); return
        }
    }

    func test_approveAll_noOp_whenAllAlreadyApproved() async {
        let entry = makeEntry(id: 1, userId: 11)
        let api = StubApprovalAPI(entries: [entry], editResult: entry)
        let vm = PendingApprovalsViewModel(api: api)
        await vm.load()
        // Approve once
        await vm.approve(entry: entry)
        api.resetCallCount()

        await vm.approveAll(employeeId: 11)

        XCTAssertEqual(api.editCallCount, 0, "No API calls when all entries already approved")
    }

    // MARK: - totalPendingCount

    func test_totalPendingCount_reflectsCurrentState() async {
        let entries = [
            makeEntry(id: 1, userId: 10),
            makeEntry(id: 2, userId: 10),
            makeEntry(id: 3, userId: 20)
        ]
        let api = StubApprovalAPI(entries: entries, editResult: entries[0])
        let vm = PendingApprovalsViewModel(api: api)
        await vm.load()
        XCTAssertEqual(vm.totalPendingCount, 3)

        await vm.approve(entry: entries[0])
        XCTAssertEqual(vm.totalPendingCount, 2)
    }
}

// MARK: - ApprovalModels Tests

final class ApprovalModelsTests: XCTestCase {

    func test_approvalEntry_withStatus_returnsNewValue() {
        let entry = makeEntry(id: 1)
        let approval = ApprovalEntry(entry: entry, status: .pending)

        let approved = approval.withStatus(.approved)

        XCTAssertEqual(approved.status, .approved)
        XCTAssertEqual(approved.entry.id, 1)
        // Original unchanged (immutability)
        XCTAssertEqual(approval.status, .pending)
    }

    func test_employeeGroup_replacing_returnsUpdatedGroup() {
        let e1 = ApprovalEntry(entry: makeEntry(id: 1), status: .pending)
        let e2 = ApprovalEntry(entry: makeEntry(id: 2), status: .pending)
        let group = EmployeeGroup(employeeId: 99, displayName: "Test", entries: [e1, e2])

        let updated = e1.withStatus(.approved)
        let newGroup = group.replacing(updated)

        XCTAssertEqual(newGroup.entries.first(where: { $0.id == 1 })?.status, .approved)
        XCTAssertEqual(newGroup.entries.first(where: { $0.id == 2 })?.status, .pending)
        // Original unchanged
        XCTAssertEqual(group.entries.first?.status, .pending)
    }

    func test_employeeGroup_approvingAll_returnsAllApproved() {
        let entries = [
            ApprovalEntry(entry: makeEntry(id: 1), status: .pending),
            ApprovalEntry(entry: makeEntry(id: 2), status: .pending)
        ]
        let group = EmployeeGroup(employeeId: 10, displayName: "X", entries: entries)

        let approved = group.approvingAll()

        XCTAssertTrue(approved.allApproved)
        XCTAssertTrue(group.entries.allSatisfy { $0.status == .pending }, "Original should be unchanged")
    }

    func test_approvalReasonPrefix_isApprovalAction_approved() {
        XCTAssertTrue(ApprovalReasonPrefix.isApprovalAction("[APPROVED]"))
        XCTAssertTrue(ApprovalReasonPrefix.isApprovalAction("[APPROVED] extra"))
    }

    func test_approvalReasonPrefix_isApprovalAction_rejected() {
        XCTAssertTrue(ApprovalReasonPrefix.isApprovalAction("[REJECTED] reason"))
    }

    func test_approvalReasonPrefix_isApprovalAction_falseForEdits() {
        XCTAssertFalse(ApprovalReasonPrefix.isApprovalAction("Manager correction"))
        XCTAssertFalse(ApprovalReasonPrefix.isApprovalAction(""))
    }

    func test_employeeGroup_pendingCount() {
        let entries = [
            ApprovalEntry(entry: makeEntry(id: 1), status: .pending),
            ApprovalEntry(entry: makeEntry(id: 2), status: .approved),
            ApprovalEntry(entry: makeEntry(id: 3), status: .rejected(reason: "bad"))
        ]
        let group = EmployeeGroup(employeeId: 1, displayName: "X", entries: entries)
        XCTAssertEqual(group.pendingCount, 1)
    }
}

// MARK: - Helpers

private func makeEntry(id: Int64, userId: Int64 = 1) -> ClockEntry {
    ClockEntry(
        id: id,
        userId: userId,
        clockIn: "2026-04-21T09:00:00Z",
        clockOut: "2026-04-21T17:00:00Z",
        totalHours: 8.0
    )
}

private enum TestApprovalError: Error, LocalizedError {
    case boom
    var errorDescription: String? { "test error" }
}

// MARK: - StubApprovalAPI

/// Test double for `APIClient`. Only implements the methods called by approval VMs.
/// `@unchecked Sendable` — mutation happens only on the calling actor (test @MainActor).
private final class StubApprovalAPI: APIClient, @unchecked Sendable {

    private let entries: [ClockEntry]
    private let listError: Error?
    private let editResult: ClockEntry?
    private let editError: Error?

    private(set) var lastReason: String?
    private(set) var editCallCount: Int = 0

    init(
        entries: [ClockEntry] = [],
        listError: Error? = nil,
        editResult: ClockEntry? = nil,
        editError: Error? = nil
    ) {
        self.entries    = entries
        self.listError  = listError
        self.editResult = editResult
        self.editError  = editError
    }

    func resetCallCount() {
        editCallCount = 0
    }

    func get<T: Decodable & Sendable>(
        _ path: String, query: [URLQueryItem]?, as type: T.Type
    ) async throws -> T {
        if let err = listError { throw err }
        if let typed = entries as? T { return typed }
        throw APITransportError.decoding("Unexpected type \(T.self)")
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T {
        editCallCount += 1
        if let err = editError { throw err }
        if let req = body as? ClockEntryEditRequest {
            lastReason = req.reason
        }
        if let result = editResult as? T { return result }
        throw APITransportError.decoding("Unexpected type \(T.self)")
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T { throw APITransportError.notImplemented }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T { throw APITransportError.notImplemented }

    func delete(_ path: String) async throws {}

    func getEnvelope<T: Decodable & Sendable>(
        _ path: String, query: [URLQueryItem]?, as type: T.Type
    ) async throws -> APIResponse<T> { throw APITransportError.notImplemented }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
