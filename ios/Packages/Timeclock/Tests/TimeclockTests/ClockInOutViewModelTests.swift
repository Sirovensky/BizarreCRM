import XCTest
@testable import Timeclock
@testable import Networking

/// Unit tests for ClockInOutViewModel.
/// All tests are @MainActor because the VM is @MainActor + @Observable.
@MainActor
final class ClockInOutViewModelTests: XCTestCase {

    // MARK: - Elapsed formatter

    func test_formatElapsed_lessThan60Seconds() {
        XCTAssertEqual(ClockInOutViewModel.formatElapsed(0),  "< 1m")
        XCTAssertEqual(ClockInOutViewModel.formatElapsed(30), "< 1m")
        XCTAssertEqual(ClockInOutViewModel.formatElapsed(59), "< 1m")
    }

    func test_formatElapsed_minuteBuckets() {
        XCTAssertEqual(ClockInOutViewModel.formatElapsed(60),   "1m")
        XCTAssertEqual(ClockInOutViewModel.formatElapsed(3599), "59m")
    }

    func test_formatElapsed_hourBuckets() {
        XCTAssertEqual(ClockInOutViewModel.formatElapsed(3600),   "1h")
        XCTAssertEqual(ClockInOutViewModel.formatElapsed(5580),   "1h 33m")
        XCTAssertEqual(ClockInOutViewModel.formatElapsed(86399),  "23h 59m")
    }

    func test_formatElapsed_dayBuckets() {
        XCTAssertEqual(ClockInOutViewModel.formatElapsed(86400),       "1d")
        XCTAssertEqual(ClockInOutViewModel.formatElapsed(86400 + 7200), "1d 2h")
    }

    // MARK: - State transitions: refresh

    func test_refresh_setsActiveState_whenClockedIn() async {
        let entry = ClockEntry(id: 1, userId: 0, clockIn: "2026-04-20T09:00:00Z")
        let stub = StubAPIClient(clockStatus: ClockStatus(isClockedIn: true, entry: entry))
        let vm = ClockInOutViewModel(api: stub)

        await vm.refresh()

        guard case .active = vm.state else {
            XCTFail("Expected .active, got \(vm.state)"); return
        }
    }

    func test_refresh_setsIdleState_whenNotClockedIn() async {
        let stub = StubAPIClient(clockStatus: ClockStatus(isClockedIn: false, entry: nil))
        let vm = ClockInOutViewModel(api: stub)

        await vm.refresh()

        guard case .idle = vm.state else {
            XCTFail("Expected .idle, got \(vm.state)"); return
        }
    }

    func test_refresh_setsIdleState_onNilStatus() async {
        let stub = StubAPIClient(clockStatus: nil)
        let vm = ClockInOutViewModel(api: stub)

        await vm.refresh()

        guard case .idle = vm.state else {
            XCTFail("Expected .idle for nil status, got \(vm.state)"); return
        }
    }

    func test_refresh_setsFailedState_onError() async {
        let stub = StubAPIClient(clockStatus: nil, statusError: TestError.boom)
        let vm = ClockInOutViewModel(api: stub)

        await vm.refresh()

        guard case .failed = vm.state else {
            XCTFail("Expected .failed, got \(vm.state)"); return
        }
    }

    // MARK: - State transitions: clockIn / clockOut

    func test_clockIn_setsActiveOnSuccess() async {
        let entry = ClockEntry(id: 10, userId: 0, clockIn: "2026-04-20T09:14:00Z")
        let stub = StubAPIClient(clockStatus: nil, clockInEntry: entry)
        let vm = ClockInOutViewModel(api: stub)

        await vm.clockIn(pin: "1234")

        guard case .active = vm.state else {
            XCTFail("Expected .active after clockIn, got \(vm.state)"); return
        }
    }

    func test_clockIn_setsFailedOnError() async {
        let stub = StubAPIClient(clockStatus: nil, clockInError: TestError.boom)
        let vm = ClockInOutViewModel(api: stub)

        await vm.clockIn(pin: "wrong")

        guard case .failed = vm.state else {
            XCTFail("Expected .failed after clockIn error, got \(vm.state)"); return
        }
    }

    func test_clockOut_setsIdleOnSuccess() async {
        let entry = ClockEntry(id: 1, userId: 0, clockIn: "2026-04-20T09:00:00Z")
        let status = ClockStatus(isClockedIn: true, entry: entry)
        let stub = StubAPIClient(clockStatus: status, clockOutEntry: ClockEntry(id: 1, userId: 0, clockIn: "2026-04-20T09:00:00Z", clockOut: "2026-04-20T17:00:00Z"))
        let vm = ClockInOutViewModel(api: stub)
        await vm.refresh() // prime to .active

        await vm.clockOut(pin: "")

        guard case .idle = vm.state else {
            XCTFail("Expected .idle after clockOut, got \(vm.state)"); return
        }
        XCTAssertEqual(vm.runningElapsed, 0)
    }

    // MARK: - Elapsed injection

    func test_elapsedIsComputedFromInjectableClock() async {
        // clockIn 1 hour ago
        let fixedNow = Date(timeIntervalSince1970: 1_745_000_000)
        let oneHourAgo = fixedNow.addingTimeInterval(-3600)
        let isoFormatter = ISO8601DateFormatter()
        let clockInStr = isoFormatter.string(from: oneHourAgo)

        let entry = ClockEntry(id: 1, userId: 0, clockIn: clockInStr)
        let stub = StubAPIClient(clockStatus: ClockStatus(isClockedIn: true, entry: entry))
        let vm = ClockInOutViewModel(api: stub, now: { fixedNow })

        await vm.refresh()

        XCTAssertGreaterThanOrEqual(vm.runningElapsed, 3590)
        XCTAssertLessThanOrEqual(vm.runningElapsed, 3610)
    }
}

// MARK: - Stubs

private enum TestError: Error, LocalizedError {
    case boom
    var errorDescription: String? { "test boom" }
}

private actor StubAPIClient: APIClient {
    private let clockStatus: ClockStatus?
    private let statusError: Error?
    private let clockInEntry: ClockEntry?
    private let clockInError: Error?
    private let clockOutEntry: ClockEntry?

    init(
        clockStatus: ClockStatus?,
        statusError: Error? = nil,
        clockInEntry: ClockEntry? = nil,
        clockInError: Error? = nil,
        clockOutEntry: ClockEntry? = nil
    ) {
        self.clockStatus = clockStatus
        self.statusError = statusError
        self.clockInEntry = clockInEntry
        self.clockInError = clockInError
        self.clockOutEntry = clockOutEntry
    }

    // Clock-specific stubs

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if let err = statusError { throw err }
        // nil clockStatus simulates a 404 so getClockStatus returns nil
        guard let status = clockStatus else {
            throw APITransportError.httpStatus(404, message: "Not found")
        }
        if let typed = status as? T { return typed }
        throw APITransportError.decoding("Unexpected type \(T.self)")
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if path.hasSuffix("/clock-in") {
            if let err = clockInError { throw err }
            if let entry = clockInEntry as? T { return entry }
        }
        if path.hasSuffix("/clock-out") {
            if let entry = clockOutEntry as? T { return entry }
        }
        throw APITransportError.decoding("Unexpected type \(T.self)")
    }

    // Unused protocol requirements

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

    func setAuthToken(_ token: String?) {}
    func setBaseURL(_ url: URL?) {}
    func currentBaseURL() -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) {}
}
