import XCTest
@testable import Employees
@testable import Networking

/// Unit tests for `EmployeeClockViewModel`.
///
/// Tests cover:
/// - Initial state is `.idle`.
/// - `refresh()` with clocked-in status → `.clockedIn`.
/// - `refresh()` with not-clocked-in status → `.notClockedIn`.
/// - `refresh()` with nil status (404) → `.notClockedIn`.
/// - `refresh()` on network error → `.failed`.
/// - `clockIn()` success → `.clockedIn`.
/// - `clockIn()` error → `.failed`.
/// - `clockOut()` success → `.notClockedIn` + elapsed resets to 0.
/// - `clockOut()` error → `.failed`.
/// - `formatElapsed` bucket boundaries.
/// - Elapsed is computed from injectable clock.
/// - `tickElapsed()` updates `elapsedSeconds` from active state.
/// - `tickElapsed()` is a no-op when not clocked in.

@MainActor
final class EmployeeClockViewModelTests: XCTestCase {

    // MARK: - formatElapsed

    func test_formatElapsed_lessThan60s() {
        XCTAssertEqual(EmployeeClockViewModel.formatElapsed(0),  "< 1m")
        XCTAssertEqual(EmployeeClockViewModel.formatElapsed(59), "< 1m")
    }

    func test_formatElapsed_minuteBucket() {
        XCTAssertEqual(EmployeeClockViewModel.formatElapsed(60),   "1m")
        XCTAssertEqual(EmployeeClockViewModel.formatElapsed(3599), "59m")
    }

    func test_formatElapsed_hourBucket() {
        XCTAssertEqual(EmployeeClockViewModel.formatElapsed(3600),  "1h")
        XCTAssertEqual(EmployeeClockViewModel.formatElapsed(5580),  "1h 33m")
        XCTAssertEqual(EmployeeClockViewModel.formatElapsed(86399), "23h 59m")
    }

    func test_formatElapsed_dayBucket() {
        XCTAssertEqual(EmployeeClockViewModel.formatElapsed(86400),        "1d")
        XCTAssertEqual(EmployeeClockViewModel.formatElapsed(86400 + 7200), "1d 2h")
    }

    // MARK: - Initial state

    func test_initialState_isIdle() {
        let vm = EmployeeClockViewModel(api: StubClockAPI(), employeeId: 1)
        if case .idle = vm.clockState { /* pass */ } else {
            XCTFail("Expected .idle, got \(vm.clockState)")
        }
    }

    // MARK: - refresh()

    func test_refresh_setClockedIn_whenServerSaysClockedIn() async {
        let entry = ClockEntry(id: 10, userId: 1, clockIn: "2026-04-20T09:00:00Z")
        let stub = StubClockAPI(status: ClockStatus(isClockedIn: true, entry: entry))
        let vm = EmployeeClockViewModel(api: stub, employeeId: 1)

        await vm.refresh()

        guard case .clockedIn = vm.clockState else {
            XCTFail("Expected .clockedIn, got \(vm.clockState)"); return
        }
    }

    func test_refresh_setNotClockedIn_whenServerSaysNotClockedIn() async {
        let stub = StubClockAPI(status: ClockStatus(isClockedIn: false, entry: nil))
        let vm = EmployeeClockViewModel(api: stub, employeeId: 1)

        await vm.refresh()

        guard case .notClockedIn = vm.clockState else {
            XCTFail("Expected .notClockedIn, got \(vm.clockState)"); return
        }
    }

    func test_refresh_setNotClockedIn_whenStatusIsNil() async {
        let stub = StubClockAPI(status: nil)  // simulates 404
        let vm = EmployeeClockViewModel(api: stub, employeeId: 1)

        await vm.refresh()

        guard case .notClockedIn = vm.clockState else {
            XCTFail("Expected .notClockedIn on nil status, got \(vm.clockState)"); return
        }
    }

    func test_refresh_setFailed_onNetworkError() async {
        let stub = StubClockAPI(status: nil, statusError: TestClockError.boom)
        let vm = EmployeeClockViewModel(api: stub, employeeId: 1)

        await vm.refresh()

        guard case .failed = vm.clockState else {
            XCTFail("Expected .failed on network error, got \(vm.clockState)"); return
        }
    }

    // MARK: - clockIn()

    func test_clockIn_setClockedIn_onSuccess() async {
        let entry = ClockEntry(id: 20, userId: 1, clockIn: "2026-04-20T10:00:00Z")
        let stub = StubClockAPI(status: nil, clockInEntry: entry)
        let vm = EmployeeClockViewModel(api: stub, employeeId: 1)

        await vm.clockIn(pin: "1234")

        guard case .clockedIn(let e) = vm.clockState else {
            XCTFail("Expected .clockedIn, got \(vm.clockState)"); return
        }
        XCTAssertEqual(e.id, 20)
    }

    func test_clockIn_setFailed_onError() async {
        let stub = StubClockAPI(status: nil, clockInError: TestClockError.boom)
        let vm = EmployeeClockViewModel(api: stub, employeeId: 1)

        await vm.clockIn(pin: "9999")

        guard case .failed = vm.clockState else {
            XCTFail("Expected .failed after clockIn error, got \(vm.clockState)"); return
        }
    }

    // MARK: - clockOut()

    func test_clockOut_setNotClockedIn_onSuccess() async {
        let openEntry  = ClockEntry(id: 1, userId: 1, clockIn: "2026-04-20T09:00:00Z")
        let closedEntry = ClockEntry(id: 1, userId: 1, clockIn: "2026-04-20T09:00:00Z",
                                     clockOut: "2026-04-20T17:00:00Z", totalHours: 8)
        let stub = StubClockAPI(
            status: ClockStatus(isClockedIn: true, entry: openEntry),
            clockOutEntry: closedEntry
        )
        let vm = EmployeeClockViewModel(api: stub, employeeId: 1)
        await vm.refresh()  // prime to .clockedIn

        await vm.clockOut(pin: "")

        guard case .notClockedIn = vm.clockState else {
            XCTFail("Expected .notClockedIn after clockOut, got \(vm.clockState)"); return
        }
        XCTAssertEqual(vm.elapsedSeconds, 0)
    }

    func test_clockOut_setFailed_onError() async {
        let entry = ClockEntry(id: 1, userId: 1, clockIn: "2026-04-20T09:00:00Z")
        let stub = StubClockAPI(
            status: ClockStatus(isClockedIn: true, entry: entry),
            clockOutError: TestClockError.boom
        )
        let vm = EmployeeClockViewModel(api: stub, employeeId: 1)
        await vm.refresh()

        await vm.clockOut(pin: "")

        guard case .failed = vm.clockState else {
            XCTFail("Expected .failed after clockOut error, got \(vm.clockState)"); return
        }
    }

    // MARK: - Elapsed

    func test_elapsedSeconds_computedFromInjectableClock() async {
        let fixedNow = Date(timeIntervalSince1970: 1_745_000_000)
        let oneHourAgo = fixedNow.addingTimeInterval(-3_600)
        let iso = ISO8601DateFormatter()
        let clockInStr = iso.string(from: oneHourAgo)

        let entry = ClockEntry(id: 1, userId: 1, clockIn: clockInStr)
        let stub = StubClockAPI(status: ClockStatus(isClockedIn: true, entry: entry))
        let vm = EmployeeClockViewModel(api: stub, employeeId: 1, now: { fixedNow })

        await vm.refresh()

        XCTAssertGreaterThanOrEqual(vm.elapsedSeconds, 3_590)
        XCTAssertLessThanOrEqual(vm.elapsedSeconds, 3_610)
    }

    func test_tickElapsed_updatesElapsedWhenClockedIn() async {
        let fixedNow = Date(timeIntervalSince1970: 1_745_000_000)
        let thirtyMinAgo = fixedNow.addingTimeInterval(-1_800)
        let iso = ISO8601DateFormatter()

        let entry = ClockEntry(id: 1, userId: 1, clockIn: iso.string(from: thirtyMinAgo))
        let stub = StubClockAPI(status: ClockStatus(isClockedIn: true, entry: entry))
        let vm = EmployeeClockViewModel(api: stub, employeeId: 1, now: { fixedNow })

        await vm.refresh()
        let elapsed1 = vm.elapsedSeconds

        // Advance the injectable clock by 30 seconds and tick
        let laterNow = fixedNow.addingTimeInterval(30)
        vm.now = { laterNow }
        vm.tickElapsed()

        XCTAssertGreaterThan(vm.elapsedSeconds, elapsed1)
    }

    func test_tickElapsed_isNoOp_whenNotClockedIn() async {
        let stub = StubClockAPI(status: ClockStatus(isClockedIn: false, entry: nil))
        let vm = EmployeeClockViewModel(api: stub, employeeId: 1)
        await vm.refresh()

        vm.tickElapsed()

        XCTAssertEqual(vm.elapsedSeconds, 0)
    }
}

// MARK: - Test doubles

private enum TestClockError: Error, LocalizedError {
    case boom
    var errorDescription: String? { "test boom" }
}

private actor StubClockAPI: APIClient {
    private let status: ClockStatus?
    private let statusError: Error?
    private let clockInEntry: ClockEntry?
    private let clockInError: Error?
    private let clockOutEntry: ClockEntry?
    private let clockOutError: Error?

    init(
        status: ClockStatus? = nil,
        statusError: Error? = nil,
        clockInEntry: ClockEntry? = nil,
        clockInError: Error? = nil,
        clockOutEntry: ClockEntry? = nil,
        clockOutError: Error? = nil
    ) {
        self.status = status
        self.statusError = statusError
        self.clockInEntry = clockInEntry
        self.clockInError = clockInError
        self.clockOutEntry = clockOutEntry
        self.clockOutError = clockOutError
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if let err = statusError { throw err }
        // nil status simulates a 404; getClockStatus catches it and returns nil
        guard let s = status else {
            throw APITransportError.httpStatus(404, message: "Not found")
        }
        if let typed = s as? T { return typed }
        throw APITransportError.decoding("Unexpected type \(T.self)")
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if path.hasSuffix("/clock-in") {
            if let err = clockInError { throw err }
            if let entry = clockInEntry as? T { return entry }
        }
        if path.hasSuffix("/clock-out") {
            if let err = clockOutError { throw err }
            if let entry = clockOutEntry as? T { return entry }
        }
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
