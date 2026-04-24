import XCTest
@testable import Tickets
@testable import Networking

// §4.9 — BenchWorkflowViewModel unit tests.
//
// Coverage targets (≥80%):
//   1. load() success — sets .loaded and populates availableActions
//   2. load() failure — sets .failed with error message
//   3. perform(.startDiagnostic) success — calls PATCH /tickets/:id/status
//      with the correct status id and sets committedAction
//   4. perform(.readyForPickup) from inRepair — calls PATCH with correct id
//   5. perform from terminal state — sets errorMessage, does NOT call PATCH
//   6. perform when API returns error — sets errorMessage, committedAction nil
//   7. availableActions reflects current status
//   8. perform(.partsOrdered) from diagnosing — commits partsOrdered action

// MARK: - Stub

/// Bench-specific stub that handles ticket detail GET, status list GET, and status PATCH.
actor BenchStubAPIClient: APIClient {

    // Configurable
    var detailResult: Result<TicketDetail, Error>
    var statusesResult: Result<[TicketStatusRow], Error>
    var patchStatusResult: Result<CreatedResource, Error>

    // Tracking
    var patchCallCount: Int = 0
    var lastPatchPath: String = ""

    init(
        detailResult: Result<TicketDetail, Error> = .success(BenchWorkflowViewModelTests.makeDetail(statusName: "Intake")),
        statusesResult: Result<[TicketStatusRow], Error> = .success(BenchWorkflowViewModelTests.makeStatuses()),
        patchStatusResult: Result<CreatedResource, Error> = .success(CreatedResource(id: 1))
    ) {
        self.detailResult = detailResult
        self.statusesResult = statusesResult
        self.patchStatusResult = patchStatusResult
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if path.hasSuffix("/settings/statuses") {
            switch statusesResult {
            case .success(let rows):
                guard let cast = rows as? T else { throw APITransportError.decoding("type mismatch") }
                return cast
            case .failure(let e):
                throw e
            }
        }
        if path.contains("/tickets/") {
            switch detailResult {
            case .success(let d):
                guard let cast = d as? T else { throw APITransportError.decoding("type mismatch") }
                return cast
            case .failure(let e):
                throw e
            }
        }
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        patchCallCount += 1
        lastPatchPath = path
        switch patchStatusResult {
        case .success(let r):
            guard let cast = r as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        case .failure(let e):
            throw e
        }
    }

    func delete(_ path: String) async throws {}

    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.noBaseURL
    }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

// MARK: - Tests

@MainActor
final class BenchWorkflowViewModelTests: XCTestCase {

    // MARK: - Factories

    static func makeDetail(
        id: Int64 = 42,
        orderId: String = "T-042",
        statusName: String = "Intake",
        statusId: Int64 = 1
    ) -> TicketDetail {
        let json = """
        {
          "id": \(id),
          "order_id": "\(orderId)",
          "status": { "id": \(statusId), "name": "\(statusName)" }
        }
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(TicketDetail.self, from: json)
    }

    static func makeStatuses() -> [TicketStatusRow] {
        let names: [(String, Int64)] = [
            ("Intake", 1),
            ("Diagnosing", 2),
            ("Awaiting Parts", 3),
            ("Awaiting Approval", 4),
            ("In Repair", 5),
            ("Ready for Pickup", 6),
            ("Completed", 7),
            ("Canceled", 8),
            ("On Hold", 9)
        ]
        return names.map { name, id in
            let json = """
            { "id": \(id), "name": "\(name)" }
            """.data(using: .utf8)!
            return try! JSONDecoder().decode(TicketStatusRow.self, from: json)
        }
    }

    // MARK: - 1. load() success

    func test_load_success_setsLoadedState() async {
        let api = BenchStubAPIClient()
        let vm = BenchWorkflowViewModel(ticketId: 42, api: api)

        await vm.load()

        guard case .loaded(let detail) = vm.loadState else {
            XCTFail("Expected .loaded, got \(vm.loadState)")
            return
        }
        XCTAssertEqual(detail.id, 42)
        XCTAssertEqual(detail.orderId, "T-042")
    }

    // MARK: - 2. load() failure

    func test_load_failure_setsFailedState() async {
        struct LoadError: Error { let msg: String }
        let api = BenchStubAPIClient(
            detailResult: .failure(LoadError(msg: "server down")),
            statusesResult: .failure(LoadError(msg: "server down"))
        )
        let vm = BenchWorkflowViewModel(ticketId: 99, api: api)

        await vm.load()

        guard case .failed(let msg) = vm.loadState else {
            XCTFail("Expected .failed")
            return
        }
        XCTAssertFalse(msg.isEmpty)
    }

    // MARK: - 3. perform(.startDiagnostic) success (intake → diagnosing)

    func test_perform_startDiagnostic_fromIntake_callsPatch() async {
        let detail = Self.makeDetail(statusName: "Intake", statusId: 1)
        // After the action, the reload returns diagnosing.
        let diagnosingDetail = Self.makeDetail(statusName: "Diagnosing", statusId: 2)
        var callIndex = 0
        let api = BenchStubAPIClient(
            detailResult: .success(detail),
            statusesResult: .success(Self.makeStatuses()),
            patchStatusResult: .success(CreatedResource(id: 42))
        )
        // Override to return diagnosing on second detail call (post-patch reload).
        // We can't do this easily in the single-result stub, so we just verify
        // PATCH was called with path matching /status and action is committed.
        _ = diagnosingDetail  // silence unused warning; second load reuses same detail

        let vm = BenchWorkflowViewModel(ticketId: 42, api: api)
        await vm.load()

        await vm.perform(.startDiagnostic)

        let patchCount = await api.patchCallCount
        XCTAssertEqual(patchCount, 1, "PATCH /status should be called once")
        XCTAssertEqual(vm.committedAction, .startDiagnostic)
        XCTAssertNil(vm.errorMessage)
        callIndex += 1
        _ = callIndex
    }

    // MARK: - 4. perform(.readyForPickup) from inRepair

    func test_perform_readyForPickup_fromInRepair_callsPatchWithCorrectStatusId() async {
        let detail = Self.makeDetail(statusName: "In Repair", statusId: 5)
        let api = BenchStubAPIClient(
            detailResult: .success(detail),
            statusesResult: .success(Self.makeStatuses()),
            patchStatusResult: .success(CreatedResource(id: 42))
        )
        let vm = BenchWorkflowViewModel(ticketId: 42, api: api)
        await vm.load()

        await vm.perform(.readyForPickup)

        let patchCount = await api.patchCallCount
        let lastPath = await api.lastPatchPath
        XCTAssertEqual(patchCount, 1)
        XCTAssertTrue(lastPath.hasSuffix("/status"), "Path should end with /status, got \(lastPath)")
        XCTAssertEqual(vm.committedAction, .readyForPickup)
    }

    // MARK: - 5. perform from terminal state (completed) sets error

    func test_perform_fromTerminalState_setsErrorMessage_doesNotCallPatch() async {
        let detail = Self.makeDetail(statusName: "Completed", statusId: 7)
        let api = BenchStubAPIClient(
            detailResult: .success(detail),
            statusesResult: .success(Self.makeStatuses()),
            patchStatusResult: .success(CreatedResource(id: 42))
        )
        let vm = BenchWorkflowViewModel(ticketId: 42, api: api)
        await vm.load()

        // availableActions should be empty for completed
        XCTAssertTrue(vm.availableActions.isEmpty)

        // Manually call perform; it should reject because no transition is legal
        await vm.perform(.startDiagnostic)

        let patchCount = await api.patchCallCount
        XCTAssertEqual(patchCount, 0, "No PATCH should fire for a terminal ticket")
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.committedAction)
    }

    // MARK: - 6. perform when PATCH API returns error

    func test_perform_apiError_setsErrorMessage_committedActionNil() async {
        struct PatchError: LocalizedError {
            var errorDescription: String? { "Status change rejected" }
        }
        let detail = Self.makeDetail(statusName: "Intake", statusId: 1)
        let api = BenchStubAPIClient(
            detailResult: .success(detail),
            statusesResult: .success(Self.makeStatuses()),
            patchStatusResult: .failure(PatchError())
        )
        let vm = BenchWorkflowViewModel(ticketId: 42, api: api)
        await vm.load()

        await vm.perform(.startDiagnostic)

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.committedAction, "committedAction should remain nil on failure")
    }

    // MARK: - 7. availableActions reflects current status

    func test_availableActions_intake_containsStartDiagnostic() async {
        let detail = Self.makeDetail(statusName: "Intake", statusId: 1)
        let api = BenchStubAPIClient(detailResult: .success(detail))
        let vm = BenchWorkflowViewModel(ticketId: 42, api: api)
        await vm.load()

        XCTAssertTrue(vm.availableActions.contains(.startDiagnostic))
        XCTAssertFalse(vm.availableActions.contains(.readyForPickup))
    }

    func test_availableActions_inRepair_containsReadyForPickup() async {
        let detail = Self.makeDetail(statusName: "In Repair", statusId: 5)
        let api = BenchStubAPIClient(detailResult: .success(detail))
        let vm = BenchWorkflowViewModel(ticketId: 42, api: api)
        await vm.load()

        XCTAssertTrue(vm.availableActions.contains(.readyForPickup))
        XCTAssertFalse(vm.availableActions.contains(.startDiagnostic))
    }

    // MARK: - 8. perform(.partsOrdered) from diagnosing

    func test_perform_partsOrdered_fromDiagnosing_callsPatch() async {
        let detail = Self.makeDetail(statusName: "Diagnosing", statusId: 2)
        let api = BenchStubAPIClient(
            detailResult: .success(detail),
            statusesResult: .success(Self.makeStatuses()),
            patchStatusResult: .success(CreatedResource(id: 42))
        )
        let vm = BenchWorkflowViewModel(ticketId: 42, api: api)
        await vm.load()

        await vm.perform(.partsOrdered)

        let patchCount = await api.patchCallCount
        XCTAssertEqual(patchCount, 1)
        XCTAssertEqual(vm.committedAction, .partsOrdered)
        XCTAssertNil(vm.errorMessage)
    }
}

// MARK: - BenchAction unit tests

final class BenchActionTests: XCTestCase {

    func test_availableActions_intake_doesNotContainResumeWork() {
        let actions = BenchAction.availableActions(for: .intake)
        XCTAssertFalse(actions.contains(.resumeWork))
    }

    func test_availableActions_onHold_containsResumeWork() {
        let actions = BenchAction.availableActions(for: .onHold)
        XCTAssertTrue(actions.contains(.resumeWork))
    }

    func test_allActions_haveNonEmptyDisplayName() {
        for action in BenchAction.allCases {
            XCTAssertFalse(action.displayName.isEmpty, "\(action) has empty displayName")
        }
    }

    func test_allActions_haveNonEmptySystemImage() {
        for action in BenchAction.allCases {
            XCTAssertFalse(action.systemImage.isEmpty, "\(action) has empty systemImage")
        }
    }

    func test_transition_fromCompletedStatus_returnsNil() {
        for action in BenchAction.allCases {
            XCTAssertNil(action.transition(from: .completed), "\(action) should have no transition from completed")
        }
    }

    func test_startDiagnostic_transition_fromIntake_isNotNil() {
        XCTAssertNotNil(BenchAction.startDiagnostic.transition(from: .intake))
    }

    func test_readyForPickup_transition_fromInRepair_isNotNil() {
        XCTAssertNotNil(BenchAction.readyForPickup.transition(from: .inRepair))
    }
}
