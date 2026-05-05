import XCTest
@testable import Employees
@testable import Networking

// MARK: - EmployeeCommissionsViewModelTests

@MainActor
final class EmployeeCommissionsViewModelTests: XCTestCase {

    // MARK: - Load: success

    func test_load_populatesCommissions_onSuccess() async {
        let commissions = [
            makeCommission(id: 1, amount: 25.0),
            makeCommission(id: 2, amount: 50.0)
        ]
        let api = StubCommissionsAPI(commissions: commissions, totalAmount: 75.0)
        let vm = EmployeeCommissionsViewModel(api: api, userIdProvider: { 42 })

        await vm.load()

        XCTAssertEqual(vm.loadState, .loaded)
        XCTAssertEqual(vm.commissions.count, 2)
        XCTAssertEqual(vm.totalAmount, 75.0, accuracy: 0.001)
    }

    func test_load_setsLoadedState_onSuccess() async {
        let api = StubCommissionsAPI(commissions: [], totalAmount: 0)
        let vm = EmployeeCommissionsViewModel(api: api, userIdProvider: { 1 })

        await vm.load()

        XCTAssertEqual(vm.loadState, .loaded)
    }

    func test_load_setsFailedState_onError() async {
        let api = StubCommissionsAPI(error: TestError.boom)
        let vm = EmployeeCommissionsViewModel(api: api, userIdProvider: { 1 })

        await vm.load()

        guard case .failed = vm.loadState else {
            XCTFail("Expected .failed, got \(vm.loadState)"); return
        }
        XCTAssertTrue(vm.commissions.isEmpty)
    }

    // MARK: - Load: userId propagation

    func test_load_passesUserIdFromProvider() async {
        let api = StubCommissionsAPI(commissions: [], totalAmount: 0)
        let vm = EmployeeCommissionsViewModel(api: api, userIdProvider: { 88 })

        await vm.load()

        XCTAssertEqual(api.lastUserId, 88)
    }

    // MARK: - Load: date filters

    func test_load_passesDateFilters_whenSet() async {
        let api = StubCommissionsAPI(commissions: [], totalAmount: 0)
        let vm = EmployeeCommissionsViewModel(api: api, userIdProvider: { 1 })
        vm.fromDate = "2026-04-01"
        vm.toDate   = "2026-04-30"

        await vm.load()

        XCTAssertEqual(api.lastFromDate, "2026-04-01")
        XCTAssertEqual(api.lastToDate,   "2026-04-30")
    }

    func test_load_passesNilDates_whenNotSet() async {
        let api = StubCommissionsAPI(commissions: [], totalAmount: 0)
        let vm = EmployeeCommissionsViewModel(api: api, userIdProvider: { 1 })
        // fromDate / toDate not set

        await vm.load()

        XCTAssertNil(api.lastFromDate)
        XCTAssertNil(api.lastToDate)
    }

    // MARK: - formattedTotal

    func test_formattedTotal_returnsCurrencyString() async {
        let api = StubCommissionsAPI(commissions: [], totalAmount: 1234.56)
        let vm = EmployeeCommissionsViewModel(api: api, userIdProvider: { 1 })
        await vm.load()

        let formatted = vm.formattedTotal
        XCTAssertTrue(formatted.contains("1,234") || formatted.contains("1234"),
                      "Expected currency formatted string, got \(formatted)")
    }

    func test_formattedTotal_isZero_beforeLoad() {
        let api = StubCommissionsAPI(commissions: [], totalAmount: 0)
        let vm = EmployeeCommissionsViewModel(api: api, userIdProvider: { 1 })

        let formatted = vm.formattedTotal
        XCTAssertTrue(formatted.contains("0"), "Expected zero value, got \(formatted)")
    }

    // MARK: - Empty state

    func test_load_emptyCommissions_loadedState() async {
        let api = StubCommissionsAPI(commissions: [], totalAmount: 0)
        let vm = EmployeeCommissionsViewModel(api: api, userIdProvider: { 1 })

        await vm.load()

        XCTAssertEqual(vm.loadState, .loaded)
        XCTAssertTrue(vm.commissions.isEmpty)
        XCTAssertEqual(vm.totalAmount, 0)
    }
}

// MARK: - Helpers

private func makeCommission(
    id: Int64,
    userId: Int64 = 1,
    amount: Double,
    ticketId: Int64? = nil
) -> EmployeeCommission {
    EmployeeCommission(
        id: id,
        userId: userId,
        ticketId: ticketId,
        amount: amount,
        createdAt: "2026-04-21T12:00:00Z"
    )
}

// MARK: - Stub

private enum TestError: Error, LocalizedError {
    case boom
    var errorDescription: String? { "test boom" }
}

/// `@unchecked Sendable` — mutation only happens on the calling actor (tests are @MainActor).
private final class StubCommissionsAPI: APIClient, @unchecked Sendable {
    private let commissions: [EmployeeCommission]
    private let totalAmount: Double
    private let error: Error?

    private(set) var lastUserId: Int64?
    private(set) var lastFromDate: String?
    private(set) var lastToDate: String?

    init(commissions: [EmployeeCommission], totalAmount: Double, error: Error? = nil) {
        self.commissions = commissions
        self.totalAmount = totalAmount
        self.error = error
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if let err = error { throw err }

        // Extract userId from path segment before "commissions".
        if let url = URL(string: "http://x" + path) {
            let components = url.pathComponents
            // Path: /api/v1/employees/:id/commissions
            if let idx = components.firstIndex(of: "commissions"), idx > 0 {
                lastUserId = Int64(components[idx - 1])
            }
        }
        lastFromDate = query?.first(where: { $0.name == "from_date" })?.value
        lastToDate   = query?.first(where: { $0.name == "to_date" })?.value

        let response = EmployeeCommissionsResponse(commissions: commissions, totalAmount: totalAmount)
        if let typed = response as? T { return typed }
        throw APITransportError.decoding("Unexpected type \(T.self)")
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.notImplemented
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
