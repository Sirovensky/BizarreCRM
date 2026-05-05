import XCTest
@testable import Employees
@testable import Networking

// MARK: - TimeOffViewModelTests

@MainActor
final class TimeOffViewModelTests: XCTestCase {

    // MARK: - Load: success

    func test_load_populatesRequests_onSuccess() async {
        let requests = [
            makeRequest(id: 1, status: .pending),
            makeRequest(id: 2, status: .approved)
        ]
        let api = StubTimeOffAPI(requests: requests)
        let vm = TimeOffViewModel(api: api, userIdProvider: { 10 })

        await vm.load()

        XCTAssertEqual(vm.loadState, .loaded)
        XCTAssertEqual(vm.requests.count, 2)
    }

    func test_load_setsLoadedState_onSuccess() async {
        let api = StubTimeOffAPI(requests: [])
        let vm = TimeOffViewModel(api: api, userIdProvider: { 1 })

        await vm.load()

        XCTAssertEqual(vm.loadState, .loaded)
    }

    func test_load_setsFailedState_onError() async {
        let api = StubTimeOffAPI(listError: TestError.boom)
        let vm = TimeOffViewModel(api: api, userIdProvider: { 1 })

        await vm.load()

        guard case .failed = vm.loadState else {
            XCTFail("Expected .failed, got \(vm.loadState)"); return
        }
        XCTAssertTrue(vm.requests.isEmpty)
    }

    func test_load_passesUserIdFromProvider() async {
        let api = StubTimeOffAPI(requests: [])
        let vm = TimeOffViewModel(api: api, userIdProvider: { 55 })

        await vm.load()

        XCTAssertEqual(api.lastUserId, 55)
    }

    func test_load_passesStatusFilter_whenSet() async {
        let api = StubTimeOffAPI(requests: [])
        let vm = TimeOffViewModel(api: api, userIdProvider: { 1 })
        vm.statusFilter = .pending

        await vm.load()

        XCTAssertEqual(api.lastStatus, .pending)
    }

    func test_load_passesNilStatus_whenNotFiltered() async {
        let api = StubTimeOffAPI(requests: [])
        let vm = TimeOffViewModel(api: api, userIdProvider: { 1 })
        vm.statusFilter = nil

        await vm.load()

        XCTAssertNil(api.lastStatus)
    }

    // MARK: - Submit: success

    func test_submit_setsSubmittedState_onSuccess() async {
        let api = StubTimeOffAPI(requests: [], submitResult: makeRequest(id: 99, status: .pending))
        let vm = TimeOffViewModel(api: api, userIdProvider: { 1 })

        await vm.submit(startDate: "2026-05-01", endDate: "2026-05-03", kind: .pto, reason: "Vacation")

        XCTAssertEqual(vm.submitState, .submitted)
    }

    func test_submit_insertsNewRequestAtFront() async {
        let existing = makeRequest(id: 1, status: .approved)
        let submitted = makeRequest(id: 99, status: .pending)
        let api = StubTimeOffAPI(requests: [existing], submitResult: submitted)
        let vm = TimeOffViewModel(api: api, userIdProvider: { 1 })
        await vm.load()

        await vm.submit(startDate: "2026-05-01", endDate: "2026-05-03", kind: .sick, reason: nil)

        XCTAssertEqual(vm.requests.count, 2)
        XCTAssertEqual(vm.requests.first?.id, 99)
    }

    func test_submit_setsFailedState_onError() async {
        let api = StubTimeOffAPI(requests: [], submitError: TestError.boom)
        let vm = TimeOffViewModel(api: api, userIdProvider: { 1 })

        await vm.submit(startDate: "2026-05-01", endDate: "2026-05-03", kind: .unpaid, reason: nil)

        guard case .failed = vm.submitState else {
            XCTFail("Expected .failed, got \(vm.submitState)"); return
        }
    }

    func test_submit_passesKindToAPI() async {
        let api = StubTimeOffAPI(requests: [], submitResult: makeRequest(id: 1, status: .pending, kind: .sick))
        let vm = TimeOffViewModel(api: api, userIdProvider: { 1 })

        await vm.submit(startDate: "2026-05-01", endDate: "2026-05-03", kind: .sick, reason: nil)

        XCTAssertEqual(api.lastSubmitKind, .sick)
    }

    func test_submit_passesReasonToAPI_whenNonEmpty() async {
        let api = StubTimeOffAPI(requests: [], submitResult: makeRequest(id: 1, status: .pending))
        let vm = TimeOffViewModel(api: api, userIdProvider: { 1 })

        await vm.submit(startDate: "2026-05-01", endDate: "2026-05-03", kind: .pto, reason: "Family event")

        XCTAssertEqual(api.lastSubmitReason, "Family event")
    }

    func test_submit_sendsNilReason_whenEmpty() async {
        let api = StubTimeOffAPI(requests: [], submitResult: makeRequest(id: 1, status: .pending))
        let vm = TimeOffViewModel(api: api, userIdProvider: { 1 })

        await vm.submit(startDate: "2026-05-01", endDate: "2026-05-03", kind: .pto, reason: "")

        XCTAssertNil(api.lastSubmitReason)
    }

    // MARK: - pendingRequests computed property

    func test_pendingRequests_filtersCorrectly() async {
        let requests = [
            makeRequest(id: 1, status: .pending),
            makeRequest(id: 2, status: .approved),
            makeRequest(id: 3, status: .pending),
            makeRequest(id: 4, status: .denied)
        ]
        let api = StubTimeOffAPI(requests: requests)
        let vm = TimeOffViewModel(api: api, userIdProvider: { 1 })
        await vm.load()

        XCTAssertEqual(vm.pendingRequests.count, 2)
        XCTAssertTrue(vm.pendingRequests.allSatisfy { $0.status == .pending })
    }

    func test_pendingRequests_emptyWhenNoRequests() {
        let api = StubTimeOffAPI(requests: [])
        let vm = TimeOffViewModel(api: api, userIdProvider: { 1 })
        XCTAssertTrue(vm.pendingRequests.isEmpty)
    }
}

// MARK: - Helpers

private func makeRequest(
    id: Int64,
    status: TimeOffStatus,
    kind: TimeOffKind = .pto
) -> TimeOffRequest {
    TimeOffRequest(
        id: id,
        userId: 1,
        startDate: "2026-05-01",
        endDate: "2026-05-03",
        kind: kind,
        status: status
    )
}

// MARK: - Stub

private enum TestError: Error, LocalizedError {
    case boom
    var errorDescription: String? { "test boom" }
}

/// `@unchecked Sendable` — mutation only happens on the calling actor (tests are @MainActor).
private final class StubTimeOffAPI: APIClient, @unchecked Sendable {

    private let requests: [TimeOffRequest]
    private let listError: Error?
    private let submitResult: TimeOffRequest?
    private let submitError: Error?

    private(set) var lastUserId: Int64?
    private(set) var lastStatus: TimeOffStatus?
    private(set) var lastSubmitKind: TimeOffKind?
    private(set) var lastSubmitReason: String?

    init(
        requests: [TimeOffRequest],
        listError: Error? = nil,
        submitResult: TimeOffRequest? = nil,
        submitError: Error? = nil
    ) {
        self.requests = requests
        self.listError = listError
        self.submitResult = submitResult
        self.submitError = submitError
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if let err = listError { throw err }
        lastUserId = query?.first(where: { $0.name == "user_id" }).flatMap { Int64($0.value ?? "") }
        let rawStatus = query?.first(where: { $0.name == "status" })?.value
        lastStatus = rawStatus.flatMap { TimeOffStatus(rawValue: $0) }

        if let typed = requests as? T { return typed }
        throw APITransportError.decoding("Unexpected type \(T.self)")
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if let err = submitError { throw err }
        if let req = body as? CreateTimeOffRequest {
            lastSubmitKind   = req.kind
            lastSubmitReason = req.reason
        }
        if let result = submitResult as? T { return result }
        throw APITransportError.decoding("Unexpected type \(T.self)")
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.notImplemented
    }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.notImplemented
    }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.notImplemented
    }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
