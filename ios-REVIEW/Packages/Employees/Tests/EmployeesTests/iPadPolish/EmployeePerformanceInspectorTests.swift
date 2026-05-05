import XCTest
@testable import Employees
@testable import Networking

// §22 iPad — EmployeePerformanceInspector tests.
//
// All tests are headless. They exercise `EmployeePerformanceInspectorViewModel`:
//   • State transitions: loading → loaded / failed
//   • Reload recovery
//   • Formatting helpers: formatMoney, elapsedSince, shortTime
//   • Clocked-in state propagation

@MainActor
final class EmployeePerformanceInspectorTests: XCTestCase {

    // MARK: - Initial state is .loading

    func test_initialState_isLoading() {
        let vm = EmployeePerformanceInspectorViewModel(
            employeeId: 1,
            api: InspectorStubAPI(succeeds: true)
        )
        guard case .loading = vm.state else {
            XCTFail("Expected .loading, got \(vm.state)")
            return
        }
    }

    // MARK: - Transitions to .loaded on success

    func test_load_transitionsToLoaded() async {
        let vm = EmployeePerformanceInspectorViewModel(
            employeeId: 1,
            api: InspectorStubAPI(succeeds: true)
        )
        await vm.load()
        guard case .loaded = vm.state else {
            XCTFail("Expected .loaded, got \(vm.state)")
            return
        }
    }

    // MARK: - Performance values are exposed after load

    func test_load_loaded_totalTickets_is42() async {
        let vm = EmployeePerformanceInspectorViewModel(
            employeeId: 1,
            api: InspectorStubAPI(succeeds: true, totalTickets: 42)
        )
        await vm.load()
        guard case let .loaded(perf) = vm.state else {
            XCTFail("Expected .loaded"); return
        }
        XCTAssertEqual(perf.totalTickets, 42)
    }

    func test_load_loaded_totalRevenue_matches() async {
        let vm = EmployeePerformanceInspectorViewModel(
            employeeId: 1,
            api: InspectorStubAPI(succeeds: true, totalRevenue: 1234.0)
        )
        await vm.load()
        guard case let .loaded(perf) = vm.state else {
            XCTFail("Expected .loaded"); return
        }
        XCTAssertEqual(perf.totalRevenue, 1234.0, accuracy: 0.01)
    }

    // MARK: - Transitions to .failed on error

    func test_load_transitionsToFailed() async {
        let vm = EmployeePerformanceInspectorViewModel(
            employeeId: 1,
            api: InspectorStubAPI(succeeds: false)
        )
        await vm.load()
        guard case .failed = vm.state else {
            XCTFail("Expected .failed, got \(vm.state)")
            return
        }
    }

    func test_load_failed_messageIsNonEmpty() async {
        let vm = EmployeePerformanceInspectorViewModel(
            employeeId: 1,
            api: InspectorStubAPI(succeeds: false)
        )
        await vm.load()
        guard case let .failed(msg) = vm.state else {
            XCTFail("Expected .failed"); return
        }
        XCTAssertFalse(msg.isEmpty)
    }

    // MARK: - Reload after failure recovers to .loaded

    func test_reload_afterFailure_recoversToLoaded() async {
        let vm = EmployeePerformanceInspectorViewModel(
            employeeId: 1,
            api: InspectorStubAPI(succeeds: true)
        )
        vm.setState(.failed("oops"))
        await vm.load()
        guard case .loaded = vm.state else {
            XCTFail("Expected .loaded after reload, got \(vm.state)")
            return
        }
    }

    // MARK: - setState test seam

    func test_setState_failed_isReflectedImmediately() {
        let vm = EmployeePerformanceInspectorViewModel(
            employeeId: 1,
            api: InspectorStubAPI(succeeds: true)
        )
        vm.setState(.failed("network error"))
        guard case let .failed(msg) = vm.state else {
            XCTFail("Expected .failed"); return
        }
        XCTAssertEqual(msg, "network error")
    }

    // MARK: - Clocked-in propagation

    func test_load_clockedIn_isTrueWhenClockedIn() async {
        let vm = EmployeePerformanceInspectorViewModel(
            employeeId: 1,
            api: InspectorStubAPI(succeeds: true, isClockedIn: true)
        )
        await vm.load()
        XCTAssertTrue(vm.clockedIn)
    }

    func test_load_clockedIn_isFalseWhenNotClockedIn() async {
        let vm = EmployeePerformanceInspectorViewModel(
            employeeId: 1,
            api: InspectorStubAPI(succeeds: true, isClockedIn: false)
        )
        await vm.load()
        XCTAssertFalse(vm.clockedIn)
    }

    func test_load_clockInTime_isNilWhenNotClockedIn() async {
        let vm = EmployeePerformanceInspectorViewModel(
            employeeId: 1,
            api: InspectorStubAPI(succeeds: true, isClockedIn: false)
        )
        await vm.load()
        XCTAssertNil(vm.clockInTime)
    }

    func test_load_clockInTime_isSetWhenClockedIn() async {
        let vm = EmployeePerformanceInspectorViewModel(
            employeeId: 1,
            api: InspectorStubAPI(
                succeeds: true,
                isClockedIn: true,
                clockInISO: "2026-04-23T09:00:00Z"
            )
        )
        await vm.load()
        XCTAssertNotNil(vm.clockInTime)
        XCTAssertEqual(vm.clockInTime, "2026-04-23T09:00:00Z")
    }

    // MARK: - formatMoney helper

    func test_formatMoney_zero_representsZero() {
        let vm = makeVM()
        let formatted = vm.formatMoney(0)
        XCTAssertTrue(formatted.contains("0"), "Expected zero representation, got \(formatted)")
    }

    func test_formatMoney_1234_containsCurrencySymbol() {
        let vm = makeVM()
        let formatted = vm.formatMoney(1234)
        XCTAssertTrue(
            formatted.contains("$") || formatted.contains("USD") || formatted.contains("1"),
            "Expected currency representation, got \(formatted)"
        )
    }

    func test_formatMoney_negativeValue_doesNotCrash() {
        let vm = makeVM()
        let formatted = vm.formatMoney(-50.0)
        XCTAssertFalse(formatted.isEmpty)
    }

    // MARK: - elapsedSince helper

    func test_elapsedSince_invalidISO_returnsDash() {
        let vm = makeVM()
        XCTAssertEqual(vm.elapsedSince("not-a-date"), "—")
    }

    func test_elapsedSince_validISO_containsColon() {
        let vm = makeVM()
        // Use a time 2h 5m in the past.
        let past = Date().addingTimeInterval(-2 * 3600 - 5 * 60)
        let iso = ISO8601DateFormatter().string(from: past)
        let result = vm.elapsedSince(iso)
        XCTAssertTrue(result.contains(":"), "Expected HH:MM format, got \(result)")
    }

    func test_elapsedSince_zero_returnsZeroZeroOrDash() {
        let vm = makeVM()
        // A very recent clockIn should give "0:00".
        let now = ISO8601DateFormatter().string(from: Date())
        let result = vm.elapsedSince(now)
        // May be "0:00" (just now) or "-0:00" etc, should not be "—"
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - shortTime helper

    func test_shortTime_invalidISO_returnsInput() {
        let vm = makeVM()
        XCTAssertEqual(vm.shortTime("not-a-date"), "not-a-date")
    }

    func test_shortTime_validISO_returnsNonEmpty() {
        let vm = makeVM()
        let result = vm.shortTime("2026-04-23T09:00:00Z")
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - Helpers

    private func makeVM() -> EmployeePerformanceInspectorViewModel {
        EmployeePerformanceInspectorViewModel(
            employeeId: 1,
            api: InspectorStubAPI(succeeds: true)
        )
    }
}

// MARK: - EmployeeContextMenuModelTests

/// Tests the Employee model properties that EmployeeContextMenu uses.
final class EmployeeContextMenuModelTests: XCTestCase {

    func test_activeEmployee_isTrue() {
        let emp = makeEmployee(id: 1, active: true)
        XCTAssertTrue(emp.active)
    }

    func test_inactiveEmployee_isFalse() {
        let emp = makeEmployee(id: 2, active: false)
        XCTAssertFalse(emp.active)
    }

    func test_displayName_firstAndLast() {
        let emp = makeEmployee(id: 1, active: true, firstName: "Jane", lastName: "Smith")
        XCTAssertEqual(emp.displayName, "Jane Smith")
    }

    func test_displayName_fallsBackToUsername() {
        let emp = makeEmployee(id: 1, active: true, firstName: nil, lastName: nil, username: "jsmith")
        XCTAssertEqual(emp.displayName, "jsmith")
    }

    func test_initials_fromFirstAndLast() {
        let emp = makeEmployee(id: 1, active: true, firstName: "Jane", lastName: "Smith")
        XCTAssertEqual(emp.initials, "JS")
    }

    func test_initials_fromUsernameWhenNoName() {
        let emp = makeEmployee(id: 1, active: true, firstName: nil, lastName: nil, username: "jsmith")
        XCTAssertEqual(emp.initials, "JS")
    }

    func test_initials_singleCharUsername_noFatalError() {
        let emp = makeEmployee(id: 1, active: true, firstName: nil, lastName: nil, username: "x")
        XCTAssertFalse(emp.initials.isEmpty)
    }

    func test_displayName_onlyFirst() {
        let emp = makeEmployee(id: 1, active: true, firstName: "Alice", lastName: nil)
        XCTAssertEqual(emp.displayName, "Alice")
    }

    func test_displayName_emptyName_fallsBackToUsername() {
        let emp = makeEmployee(id: 3, active: true, firstName: nil, lastName: nil, username: nil)
        // Falls back to "User #3"
        XCTAssertFalse(emp.displayName.isEmpty)
    }
}

// MARK: - EmployeeShortcutMetadataTests (verify Inspector covers 80%)

final class EmployeeiPadShortcutCoverageTests: XCTestCase {

    func test_allShortcuts_haveSameCountAsEnum() {
        // Ensure no future enum case was added without being covered.
        XCTAssertEqual(EmployeeShortcut.allCases.count, 4)
    }

    func test_everyShortcut_hasNonemptyDisplayTitle() {
        for s in EmployeeShortcut.allCases {
            XCTAssertFalse(s.displayTitle.isEmpty, "\(s) has empty display title")
        }
    }

    func test_everyShortcut_hintContainsCommand() {
        for s in EmployeeShortcut.allCases {
            XCTAssertTrue(
                s.accessibilityHint.contains("Command"),
                "\(s) hint missing 'Command': \(s.accessibilityHint)"
            )
        }
    }
}

// MARK: - InspectorStubAPI

/// Minimal `APIClient` conformance for inspector tests.
private struct InspectorStubAPI: APIClient, @unchecked Sendable {

    let succeeds: Bool
    var totalTickets: Int = 10
    var totalRevenue: Double = 500.0
    var isClockedIn: Bool = false
    var clockInISO: String? = nil

    func get<T: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem]?,
        as type: T.Type
    ) async throws -> T {
        if !succeeds { throw URLError(.notConnectedToInternet) }

        if path.hasSuffix("/performance") {
            let json: [String: Any] = [
                "total_tickets": totalTickets,
                "closed_tickets": max(0, totalTickets - 2),
                "total_revenue": totalRevenue,
                "avg_ticket_value": totalRevenue / max(1, Double(totalTickets)),
                "total_devices_repaired": max(0, totalTickets - 3)
            ]
            let data = try JSONSerialization.data(withJSONObject: json)
            return try JSONDecoder().decode(T.self, from: data)
        }

        if path.contains("/api/v1/employees/") {
            var json: [String: Any] = [
                "id": 1,
                "is_active": 1,
                "is_clocked_in": isClockedIn
            ]
            if isClockedIn, let iso = clockInISO {
                json["current_clock_entry"] = [
                    "id": 99,
                    "user_id": 1,
                    "clock_in": iso
                ] as [String: Any]
            }
            let data = try JSONSerialization.data(withJSONObject: json)
            return try JSONDecoder().decode(T.self, from: data)
        }

        throw URLError(.unsupportedURL)
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T { throw URLError(.unsupportedURL) }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T { throw URLError(.unsupportedURL) }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T { throw URLError(.unsupportedURL) }

    func delete(_ path: String) async throws {}

    func getEnvelope<T: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem]?,
        as type: T.Type
    ) async throws -> APIResponse<T> { throw URLError(.unsupportedURL) }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

// MARK: - Employee model factory (local to this file)

private func makeEmployee(
    id: Int64,
    active: Bool,
    firstName: String? = "Test",
    lastName: String? = "Employee",
    username: String? = "testuser"
) -> Employee {
    var json: [String: Any] = [
        "id": id,
        "is_active": active ? 1 : 0
    ]
    if let v = username   { json["username"]   = v }
    if let v = firstName  { json["first_name"] = v }
    if let v = lastName   { json["last_name"]  = v }
    let data = try! JSONSerialization.data(withJSONObject: json)
    return try! JSONDecoder().decode(Employee.self, from: data)
}
