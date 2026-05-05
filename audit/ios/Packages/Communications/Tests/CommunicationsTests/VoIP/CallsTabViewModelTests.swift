import XCTest
@testable import Communications
@testable import Networking

// MARK: - Mock Call Log Repository

actor MockCallLogRepository: CallLogRepository {
    var callsResult: Result<[CallLogEntry], Error> = .success([])
    var initiateResult: Result<Int64, Error> = .success(42)
    var hangupCalled: Bool = false
    var hangupCallId: Int64? = nil

    func listCalls(pageSize: Int) async throws -> [CallLogEntry] {
        switch callsResult {
        case .success(let calls): return calls
        case .failure(let err): throw err
        }
    }

    func initiateCall(to phoneNumber: String, customerId: Int64?) async throws -> Int64 {
        switch initiateResult {
        case .success(let id): return id
        case .failure(let err): throw err
        }
    }

    func hangupCall(id: Int64) async throws {
        hangupCalled = true
        hangupCallId = id
    }
}

// MARK: - Helpers

private func makeEntry(id: Int64, direction: String = "inbound", duration: Int? = 120) -> CallLogEntry {
    CallLogEntry(
        id: id,
        direction: direction,
        phoneNumber: "+15555550100",
        customerId: nil,
        customerName: "Test Customer",
        startedAt: "2026-04-26T10:00:00Z",
        durationSeconds: duration,
        recordingUrl: nil,
        transcriptText: nil
    )
}

// MARK: - Tests

@MainActor
final class CallsTabViewModelTests: XCTestCase {

    // MARK: load — success

    func test_load_populatesCalls() async {
        let repo = MockCallLogRepository()
        let entries = [makeEntry(id: 1), makeEntry(id: 2, direction: "outbound")]
        await repo.set(callsResult: .success(entries))

        let vm = CallsTabViewModel(repo: repo)
        await vm.load()

        XCTAssertEqual(vm.calls.count, 2)
        XCTAssertNil(vm.errorMessage)
        XCTAssertNil(vm.infoMessage)
    }

    // MARK: load — empty list shows info banner

    func test_load_empty_showsInfoMessage() async {
        let repo = MockCallLogRepository()
        await repo.set(callsResult: .success([]))

        let vm = CallsTabViewModel(repo: repo)
        await vm.load()

        XCTAssertTrue(vm.calls.isEmpty)
        XCTAssertNotNil(vm.infoMessage)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: load — 404 shows info not error

    func test_load_404_showsInfoNotError() async {
        let repo = MockCallLogRepository()
        await repo.set(callsResult: .failure(APITransportError.httpStatus(404, "Not Found")))

        let vm = CallsTabViewModel(repo: repo)
        await vm.load()

        XCTAssertNotNil(vm.infoMessage)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: load — other error shows errorMessage

    func test_load_networkError_showsErrorMessage() async {
        let repo = MockCallLogRepository()
        await repo.set(callsResult: .failure(APITransportError.noBaseURL))

        let vm = CallsTabViewModel(repo: repo)
        await vm.load()

        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: filtered views

    func test_filteredViews_inbound_outbound_missed() async {
        let repo = MockCallLogRepository()
        let entries = [
            makeEntry(id: 1, direction: "inbound", duration: 120),   // inbound, answered
            makeEntry(id: 2, direction: "inbound", duration: 0),      // missed (inbound + 0 duration)
            makeEntry(id: 3, direction: "outbound", duration: 60),    // outbound
        ]
        await repo.set(callsResult: .success(entries))

        let vm = CallsTabViewModel(repo: repo)
        await vm.load()

        XCTAssertEqual(vm.inboundCalls.count, 2)
        XCTAssertEqual(vm.outboundCalls.count, 1)
        XCTAssertEqual(vm.missedCalls.count, 1)
        XCTAssertEqual(vm.missedCalls.first?.id, 2)
    }

    // MARK: initiate call — success

    func test_initiateCall_setsActiveCallId() async {
        let repo = MockCallLogRepository()
        await repo.set(initiateResult: .success(99))

        let vm = CallsTabViewModel(repo: repo)
        await vm.initiateCall(to: "+15555550100")

        XCTAssertEqual(vm.activeOutboundCallId, 99)
    }

    // MARK: initiate call — 404 shows info

    func test_initiateCall_404_showsInfo() async {
        let repo = MockCallLogRepository()
        await repo.set(initiateResult: .failure(APITransportError.httpStatus(404, "Not Found")))

        let vm = CallsTabViewModel(repo: repo)
        await vm.initiateCall(to: "+15555550100")

        XCTAssertNil(vm.activeOutboundCallId)
        XCTAssertNotNil(vm.infoMessage)
    }

    // MARK: hangup — calls repo and clears active call

    func test_hangup_callsRepoAndClearsState() async {
        let repo = MockCallLogRepository()
        await repo.set(callsResult: .success([]))
        await repo.set(initiateResult: .success(77))

        let vm = CallsTabViewModel(repo: repo)
        await vm.initiateCall(to: "+15555550100")
        XCTAssertEqual(vm.activeOutboundCallId, 77)

        await vm.hangup()

        let wasCalled = await repo.hangupCalled
        XCTAssertTrue(wasCalled)
        XCTAssertNil(vm.activeOutboundCallId)
    }

    // MARK: recording playback state

    func test_openRecordingPlayback_setsSelectedEntry() async {
        let repo = MockCallLogRepository()
        let vm = CallsTabViewModel(repo: repo)
        let entry = makeEntry(id: 5)

        vm.openRecordingPlayback(for: entry)

        XCTAssertEqual(vm.selectedForPlayback?.id, 5)
    }

    // MARK: transcript state

    func test_openTranscription_setsSelectedEntry() async {
        let repo = MockCallLogRepository()
        let vm = CallsTabViewModel(repo: repo)
        let entry = makeEntry(id: 7)

        vm.openTranscription(for: entry)

        XCTAssertEqual(vm.selectedForTranscript?.id, 7)
    }

    // MARK: clearError

    func test_clearError() async {
        let repo = MockCallLogRepository()
        await repo.set(callsResult: .failure(APITransportError.noBaseURL))
        let vm = CallsTabViewModel(repo: repo)
        await vm.load()
        XCTAssertNotNil(vm.errorMessage)

        vm.clearError()

        XCTAssertNil(vm.errorMessage)
    }
}

// MARK: - Actor helper for test mutation

private extension MockCallLogRepository {
    func set(callsResult: Result<[CallLogEntry], Error>) {
        self.callsResult = callsResult
    }
    func set(initiateResult: Result<Int64, Error>) {
        self.initiateResult = initiateResult
    }
}
