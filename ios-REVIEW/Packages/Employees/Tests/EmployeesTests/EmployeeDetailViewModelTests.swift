import XCTest
@testable import Employees
@testable import Networking

// MARK: - EmployeeDetailViewModelTests

@MainActor
final class EmployeeDetailViewModelTests: XCTestCase {

    // MARK: - Load success

    func test_load_success_setsLoaded() async {
        let api = StubDetailAPI(detail: .fixture(), performance: .fixture())
        let vm = EmployeeDetailViewModel(employeeId: 1, api: api)
        await vm.load()
        XCTAssertEqual(vm.loadState, .loaded)
    }

    func test_load_success_populatesDetail() async {
        let detail = EmployeeDetail.fixture(id: 42, firstName: "Carol")
        let api = StubDetailAPI(detail: detail, performance: .fixture())
        let vm = EmployeeDetailViewModel(employeeId: 42, api: api)
        await vm.load()
        XCTAssertEqual(vm.detail?.displayName, "Carol Smith")
    }

    func test_load_success_populatesPerformance() async {
        let perf = EmployeePerformance.fixture(totalTickets: 15, closedTickets: 10)
        let api = StubDetailAPI(detail: .fixture(), performance: perf)
        let vm = EmployeeDetailViewModel(employeeId: 1, api: api)
        await vm.load()
        XCTAssertEqual(vm.performance?.totalTickets, 15)
    }

    func test_load_failure_setsFailed() async {
        let api = StubDetailAPI(error: APITransportError.noBaseURL)
        let vm = EmployeeDetailViewModel(employeeId: 1, api: api)
        await vm.load()
        guard case .failed = vm.loadState else {
            XCTFail("Expected .failed, got \(vm.loadState)"); return
        }
    }

    // MARK: - Commission summary

    func test_commissionSummary_sumsAmounts() async {
        let commissions: [EmployeeCommission] = [
            .fixture(id: 1, amount: 50),
            .fixture(id: 2, amount: 25.50),
        ]
        let detail = EmployeeDetail.fixture(commissions: commissions)
        let api = StubDetailAPI(detail: detail, performance: .fixture())
        let vm = EmployeeDetailViewModel(employeeId: 1, api: api)
        await vm.load()
        XCTAssertEqual(vm.commissionSummary, 75.50, accuracy: 0.01)
    }

    func test_commissionSummary_nilCommissions_isZero() async {
        let detail = EmployeeDetail.fixture(commissions: nil)
        let api = StubDetailAPI(detail: detail, performance: .fixture())
        let vm = EmployeeDetailViewModel(employeeId: 1, api: api)
        await vm.load()
        XCTAssertEqual(vm.commissionSummary, 0)
    }

    // MARK: - isActive

    func test_isActive_activeEmployee() async {
        let api = StubDetailAPI(detail: .fixture(isActive: 1), performance: .fixture())
        let vm = EmployeeDetailViewModel(employeeId: 1, api: api)
        await vm.load()
        XCTAssertTrue(vm.isActive)
    }

    func test_isActive_inactiveEmployee() async {
        let api = StubDetailAPI(detail: .fixture(isActive: 0), performance: .fixture())
        let vm = EmployeeDetailViewModel(employeeId: 1, api: api)
        await vm.load()
        XCTAssertFalse(vm.isActive)
    }

    // MARK: - Current shift

    func test_currentShift_nilWhenNotClockedIn() async {
        let detail = EmployeeDetail.fixture(isClockedIn: false, currentClockEntry: nil)
        let api = StubDetailAPI(detail: detail, performance: .fixture())
        let vm = EmployeeDetailViewModel(employeeId: 1, api: api)
        await vm.load()
        XCTAssertNil(vm.currentShift)
    }

    func test_currentShift_returnsEntryWhenClockedIn() async {
        let entry = ClockEntry.fixture(id: 77)
        let detail = EmployeeDetail.fixture(isClockedIn: true, currentClockEntry: entry)
        let api = StubDetailAPI(detail: detail, performance: .fixture())
        let vm = EmployeeDetailViewModel(employeeId: 1, api: api)
        await vm.load()
        XCTAssertEqual(vm.currentShift?.id, 77)
    }

    // MARK: - Role assignment flow

    func test_requestRoleChange_setsPendingRoleId() async {
        let api = StubDetailAPI(detail: .fixture(), performance: .fixture())
        let vm = EmployeeDetailViewModel(employeeId: 1, api: api)
        await vm.load()
        vm.requestRoleChange(roleId: 5)
        XCTAssertEqual(vm.pendingRoleId, 5)
        XCTAssertTrue(vm.showRoleConfirm)
    }

    func test_confirmRoleChange_callsAssignRole() async {
        let api = StubDetailAPI(detail: .fixture(), performance: .fixture())
        let vm = EmployeeDetailViewModel(employeeId: 1, api: api)
        await vm.load()
        vm.requestRoleChange(roleId: 3)
        await vm.confirmRoleChange()
        XCTAssertTrue(api.assignRoleCalled)
    }

    func test_confirmRoleChange_clearsPendingId() async {
        let api = StubDetailAPI(detail: .fixture(), performance: .fixture())
        let vm = EmployeeDetailViewModel(employeeId: 1, api: api)
        await vm.load()
        vm.requestRoleChange(roleId: 2)
        await vm.confirmRoleChange()
        XCTAssertNil(vm.pendingRoleId)
    }

    func test_confirmRoleChange_failure_setsFailed() async {
        let api = StubDetailAPI(
            detail: .fixture(),
            performance: .fixture(),
            assignRoleError: APITransportError.noBaseURL
        )
        let vm = EmployeeDetailViewModel(employeeId: 1, api: api)
        await vm.load()
        vm.requestRoleChange(roleId: 2)
        await vm.confirmRoleChange()
        guard case .failed = vm.actionState else {
            XCTFail("Expected .failed, got \(vm.actionState)"); return
        }
    }

    // MARK: - Deactivate / reactivate

    func test_confirmDeactivate_callsSetActive_false() async {
        let api = StubDetailAPI(detail: .fixture(isActive: 1), performance: .fixture())
        let vm = EmployeeDetailViewModel(employeeId: 1, api: api)
        await vm.load()
        await vm.confirmDeactivate()
        XCTAssertEqual(api.setActiveArg, false)
    }

    func test_confirmReactivate_callsSetActive_true() async {
        let api = StubDetailAPI(detail: .fixture(isActive: 0), performance: .fixture())
        let vm = EmployeeDetailViewModel(employeeId: 1, api: api)
        await vm.load()
        await vm.confirmReactivate()
        XCTAssertEqual(api.setActiveArg, true)
    }

    func test_confirmDeactivate_failure_setsFailed() async {
        let api = StubDetailAPI(
            detail: .fixture(isActive: 1),
            performance: .fixture(),
            setActiveError: APITransportError.noBaseURL
        )
        let vm = EmployeeDetailViewModel(employeeId: 1, api: api)
        await vm.load()
        await vm.confirmDeactivate()
        guard case .failed = vm.actionState else {
            XCTFail("Expected .failed, got \(vm.actionState)"); return
        }
    }

    // MARK: - Available roles

    func test_availableRoles_onlyActiveRoles() async {
        let roles = [
            RoleRow(id: 1, name: "admin",      description: nil, isActive: 1, createdAt: ""),
            RoleRow(id: 2, name: "archived",   description: nil, isActive: 0, createdAt: ""),
            RoleRow(id: 3, name: "technician", description: nil, isActive: 1, createdAt: ""),
        ]
        let api = StubDetailAPI(detail: .fixture(), performance: .fixture(), roles: roles)
        let vm = EmployeeDetailViewModel(employeeId: 1, api: api)
        await vm.load()
        XCTAssertEqual(vm.availableRoles.map { $0.name }, ["admin", "technician"])
    }

    // MARK: - formattedCommissionTotal

    func test_formattedCommissionTotal_containsDollarSign() async {
        let commissions = [EmployeeCommission.fixture(id: 1, amount: 120)]
        let api = StubDetailAPI(detail: .fixture(commissions: commissions), performance: .fixture())
        let vm = EmployeeDetailViewModel(employeeId: 1, api: api)
        await vm.load()
        XCTAssertTrue(vm.formattedCommissionTotal.contains("$") || vm.formattedCommissionTotal.contains("120"))
    }
}

// MARK: - StubDetailAPI

private final class StubDetailAPI: APIClient, @unchecked Sendable {
    private let detail: EmployeeDetail?
    private let performance: EmployeePerformance?
    private let roles: [RoleRow]
    private let error: Error?
    private let assignRoleError: Error?
    private let setActiveError: Error?

    private(set) var assignRoleCalled = false
    private(set) var setActiveArg: Bool?

    init(
        detail: EmployeeDetail? = nil,
        performance: EmployeePerformance? = nil,
        roles: [RoleRow] = [],
        error: Error? = nil,
        assignRoleError: Error? = nil,
        setActiveError: Error? = nil
    ) {
        self.detail = detail
        self.performance = performance
        self.roles = roles
        self.error = error
        self.assignRoleError = assignRoleError
        self.setActiveError = setActiveError
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if let err = error { throw err }
        if path.hasSuffix("/performance") {
            guard let p = performance, let cast = p as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        }
        if path.hasPrefix("/api/v1/employees/") {
            guard let d = detail, let cast = d as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        }
        if path == "/api/v1/roles" {
            guard let cast = roles as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        }
        throw APITransportError.notImplemented
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if path.contains("/roles/users/") {
            if let err = assignRoleError { throw err }
            assignRoleCalled = true
            let dict: [String: Any] = ["user_id": 1, "role_id": 1]
            let data = try JSONSerialization.data(withJSONObject: dict)
            return try JSONDecoder().decode(T.self, from: data)
        }
        if path.contains("/settings/users/") {
            if let err = setActiveError { throw err }
            var resolvedIsActive: Int = 1
            if let bodyData = try? JSONEncoder().encode(body),
               let dict = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
               let isActive = dict["is_active"] as? Int {
                resolvedIsActive = isActive
                setActiveArg = isActive != 0
            }
            let dict: [String: Any] = ["id": 1, "is_active": resolvedIsActive]
            let data = try JSONSerialization.data(withJSONObject: dict)
            return try JSONDecoder().decode(T.self, from: data)
        }
        throw APITransportError.notImplemented
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.notImplemented }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.notImplemented }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.notImplemented }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

// MARK: - Fixtures

extension EmployeeDetail {
    static func fixture(
        id: Int64 = 1,
        firstName: String = "Alice",
        lastName: String = "Smith",
        role: String? = "technician",
        isActive: Int = 1,
        isClockedIn: Bool? = nil,
        currentClockEntry: ClockEntry? = nil,
        commissions: [EmployeeCommission]? = nil
    ) -> EmployeeDetail {
        var dict: [String: Any] = [
            "id":         id,
            "first_name": firstName,
            "last_name":  lastName,
            "is_active":  isActive,
        ]
        if let r = role { dict["role"] = r }
        if let ci = isClockedIn { dict["is_clocked_in"] = ci }
        if let ce = currentClockEntry,
           let ceData = try? JSONEncoder().encode(ce),
           let ceDict = try? JSONSerialization.jsonObject(with: ceData) {
            dict["current_clock_entry"] = ceDict
        }
        if let cs = commissions,
           let csData = try? JSONEncoder().encode(cs),
           let csArr = try? JSONSerialization.jsonObject(with: csData) {
            dict["commissions"] = csArr
        }
        let data = try! JSONSerialization.data(withJSONObject: dict)
        // EmployeeDetail uses explicit CodingKeys with snake_case keys,
        // so plain JSONDecoder is correct (no convertFromSnakeCase).
        return try! JSONDecoder().decode(EmployeeDetail.self, from: data)
    }
}

extension EmployeePerformance {
    static func fixture(
        totalTickets: Int = 5,
        closedTickets: Int = 3,
        totalRevenue: Double = 500,
        avgTicketValue: Double = 100,
        avgRepairHours: Double? = 2.5,
        totalDevicesRepaired: Int = 3
    ) -> EmployeePerformance {
        var dict: [String: Any] = [
            "total_tickets":          totalTickets,
            "closed_tickets":         closedTickets,
            "total_revenue":          totalRevenue,
            "avg_ticket_value":       avgTicketValue,
            "total_devices_repaired": totalDevicesRepaired,
        ]
        if let h = avgRepairHours { dict["avg_repair_hours"] = h }
        let data = try! JSONSerialization.data(withJSONObject: dict)
        // EmployeePerformance uses explicit CodingKeys with snake_case keys.
        return try! JSONDecoder().decode(EmployeePerformance.self, from: data)
    }
}

extension EmployeeCommission {
    static func fixture(id: Int64 = 1, amount: Double = 10.0) -> EmployeeCommission {
        EmployeeCommission(
            id: id,
            userId: 1,
            amount: amount,
            createdAt: "2026-04-01T12:00:00Z"
        )
    }
}

extension ClockEntry {
    static func fixture(
        id: Int64 = 1,
        userId: Int64 = 1,
        clockIn: String = "2026-04-23T08:00:00Z"
    ) -> ClockEntry {
        let dict: [String: Any] = [
            "id":       id,
            "user_id":  userId,
            "clock_in": clockIn,
        ]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        // ClockEntry uses explicit CodingKeys with snake_case keys.
        return try! JSONDecoder().decode(ClockEntry.self, from: data)
    }
}

// Employee.fixture(id:firstName:lastName:) declared in EmployeeCachedRepositoryTests.swift
// and shared across this test target.
