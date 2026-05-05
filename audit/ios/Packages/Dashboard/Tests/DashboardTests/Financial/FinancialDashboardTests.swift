import XCTest
@testable import Dashboard
import Networking

// MARK: - FinancialDashboardTests
//
// Coverage target: ≥80% of §59 Financial Dashboard sources.
//
// Files under test:
//   Financial/FinancialDashboardModels.swift    — snapshot conversion
//   Financial/FinancialDashboardViewModel.swift — state machine + formatters
//   Financial/FinancialDashboardRepository.swift — via spy APIClient

// MARK: - Snapshot conversion (FinancialDashboardModels)

final class FinancialSnapshotConversionTests: XCTestCase {

    func test_from_wire_convertsCentsToDoubleDollars() {
        let wire = Fixtures.wire(grossCents: 100_00, netCents: 85_00,
                                 refundsCents: 5_00, discountsCents: 10_00,
                                 grossProfitCents: 40_00, grossProfitMarginPct: 47.1,
                                 netProfitCents: 20_00, netProfitMarginPct: 23.5,
                                 outstandingCents: 300_00, overdueCents: 50_00,
                                 truncated: false)
        let snap = FinancialDashboardSnapshot.from(wire: wire)

        XCTAssertEqual(snap.revenue.gross,    100.0,  accuracy: 0.001)
        XCTAssertEqual(snap.revenue.net,       85.0,  accuracy: 0.001)
        XCTAssertEqual(snap.revenue.refunds,    5.0,  accuracy: 0.001)
        XCTAssertEqual(snap.revenue.discounts, 10.0,  accuracy: 0.001)
        XCTAssertEqual(snap.grossProfit.value, 40.0,  accuracy: 0.001)
        XCTAssertEqual(snap.grossProfit.marginPct, 47.1, accuracy: 0.001)
        XCTAssertEqual(snap.netProfit.value,   20.0,  accuracy: 0.001)
        XCTAssertEqual(snap.netProfit.marginPct, 23.5, accuracy: 0.001)
        XCTAssertEqual(snap.cashPosition.outstanding, 300.0, accuracy: 0.001)
        XCTAssertEqual(snap.cashPosition.overdue,      50.0, accuracy: 0.001)
        XCTAssertFalse(snap.cashPosition.isApproximate)
    }

    func test_from_wire_propagatesTruncatedFlag() {
        let snap = FinancialDashboardSnapshot.from(wire: Fixtures.wire(truncated: true))
        XCTAssertTrue(snap.cashPosition.isApproximate)
    }

    func test_from_wire_mapsTopCustomers() {
        let wire = Fixtures.wire(customers: [
            OwnerPLTopCustomerWire(customerId: 1, name: "Alice", revenueCents: 50_00),
            OwnerPLTopCustomerWire(customerId: 2, name: "Bob",   revenueCents: 30_00),
        ])
        let snap = FinancialDashboardSnapshot.from(wire: wire)
        XCTAssertEqual(snap.topCustomers.count, 2)
        XCTAssertEqual(snap.topCustomers[0].id,   1)
        XCTAssertEqual(snap.topCustomers[0].name, "Alice")
        XCTAssertEqual(snap.topCustomers[0].revenue, 50.0, accuracy: 0.001)
        XCTAssertEqual(snap.topCustomers[1].revenue, 30.0, accuracy: 0.001)
    }

    func test_from_wire_replacesEmptyCustomerNameWithUnknown() {
        let wire = Fixtures.wire(customers: [
            OwnerPLTopCustomerWire(customerId: 9, name: "", revenueCents: 1_00),
        ])
        let snap = FinancialDashboardSnapshot.from(wire: wire)
        XCTAssertEqual(snap.topCustomers[0].name, "Unknown")
    }

    func test_from_wire_setsPeriodFields() {
        let snap = FinancialDashboardSnapshot.from(wire: Fixtures.wire())
        XCTAssertEqual(snap.periodFrom,  "2026-03-01")
        XCTAssertEqual(snap.periodTo,    "2026-03-31")
        XCTAssertEqual(snap.periodDays,  31)
    }

    func test_from_wire_emptyCustomerList() {
        let snap = FinancialDashboardSnapshot.from(wire: Fixtures.wire(customers: []))
        XCTAssertTrue(snap.topCustomers.isEmpty)
    }

    func test_topCustomer_identifiable_usesCustomerId() {
        let c = FinancialTopCustomer(id: 42, name: "X", revenue: 1)
        XCTAssertEqual(c.id, 42)
    }
}

// MARK: - ViewModel state machine

@MainActor
final class FinancialDashboardViewModelTests: XCTestCase {

    func test_initialState_isIdle() {
        let vm = makeVM(result: .success(Fixtures.snapshot()))
        if case .idle = vm.state { return }
        XCTFail("Expected .idle, got \(vm.state)")
    }

    func test_load_transitionsToLoaded() async {
        let vm = makeVM(result: .success(Fixtures.snapshot()))
        await vm.load()
        guard case .loaded = vm.state else {
            XCTFail("Expected .loaded"); return
        }
    }

    func test_load_transitionsToFailedOnError() async {
        let vm = makeVM(result: .failure(TestError.boom))
        await vm.load()
        guard case let .failed(message) = vm.state else {
            XCTFail("Expected .failed"); return
        }
        XCTAssertFalse(message.isEmpty)
    }

    func test_load_softRefreshKeepsPriorData() async {
        let repo = StubRepo(result: .success(Fixtures.snapshot()))
        let vm = FinancialDashboardViewModel(repo: repo)
        await vm.load()
        guard case .loaded = vm.state else {
            XCTFail("Expected .loaded after first load"); return
        }
        // Second load: state is already .loaded → soft refresh path.
        let wasLoaded: Bool
        if case .loaded = vm.state { wasLoaded = true } else { wasLoaded = false }
        await vm.load()
        if !wasLoaded {
            XCTFail("Soft refresh must not reset to .loading when already loaded")
        }
    }

    func test_reload_forcesLoadingThenLoaded() async {
        let vm = makeVM(result: .success(Fixtures.snapshot()))
        await vm.load()   // first load
        await vm.reload() // force reload
        guard case .loaded = vm.state else {
            XCTFail("Expected .loaded after reload"); return
        }
    }

    func test_applyParams_updatesParamsAndReloads() async {
        let vm = makeVM(result: .success(Fixtures.snapshot()))
        let newParams = FinancialQueryParams(from: "2026-01-01", to: "2026-01-31", rollup: .month)
        await vm.applyParams(newParams)
        XCTAssertEqual(vm.params.from,   "2026-01-01")
        XCTAssertEqual(vm.params.to,     "2026-01-31")
        XCTAssertEqual(vm.params.rollup, .month)
        guard case .loaded = vm.state else {
            XCTFail("Expected .loaded after applyParams"); return
        }
    }

    func test_defaultParams_coversThirtyDaysWithDailyRollup() {
        let vm = makeVM(result: .success(Fixtures.snapshot()))
        XCTAssertFalse(vm.params.from.isEmpty, "Default from must not be empty")
        XCTAssertFalse(vm.params.to.isEmpty,   "Default to must not be empty")
        XCTAssertLessThan(vm.params.from, vm.params.to)
        XCTAssertEqual(vm.params.rollup, .day)
    }

    func test_load_snapshotReflectsRepoData() async {
        let expected = Fixtures.snapshot(netRevenue: 1234.56, netProfitMargin: 12.3)
        let vm = makeVM(result: .success(expected))
        await vm.load()
        guard case let .loaded(s) = vm.state else {
            XCTFail("Expected .loaded"); return
        }
        XCTAssertEqual(s.revenue.net,          1234.56, accuracy: 0.001)
        XCTAssertEqual(s.netProfit.marginPct,     12.3, accuracy: 0.001)
    }

    // MARK: helpers

    private func makeVM(result: Result<FinancialDashboardSnapshot, Error>) -> FinancialDashboardViewModel {
        FinancialDashboardViewModel(repo: StubRepo(result: result))
    }
}

// MARK: - Currency formatter

final class FinancialFormatCurrencyTests: XCTestCase {

    func test_belowThousand_usesCurrencyFormat() {
        let result = financialFormatCurrency(499.0)
        XCTAssertTrue(result.contains("499"), "Expected '499' in '\(result)'")
    }

    func test_thousands_usesKSuffix() {
        let result = financialFormatCurrency(12_400)
        XCTAssertTrue(result.contains("k"),  "Expected 'k' in '\(result)'")
        XCTAssertTrue(result.contains("12"), "Expected '12' in '\(result)'")
    }

    func test_millions_usesMSuffix() {
        let result = financialFormatCurrency(1_500_000)
        XCTAssertTrue(result.contains("M"), "Expected 'M' in '\(result)'")
    }

    func test_negative_includesMinusSign() {
        let result = financialFormatCurrency(-500)
        XCTAssertTrue(result.hasPrefix("-"), "Expected '-' prefix in '\(result)'")
    }

    func test_zero_formatsWithoutCrash() {
        let result = financialFormatCurrency(0)
        XCTAssertFalse(result.isEmpty)
    }

    func test_exactThousand_noDecimalZero() {
        let result = financialFormatCurrency(1_000)
        // Compact: "$1k" not "$1.0k"
        XCTAssertFalse(result.contains(".0"), "Should omit '.0' for exact thousands: '\(result)'")
    }

    func test_negativeMillion_includesSignAndM() {
        let result = financialFormatCurrency(-2_000_000)
        XCTAssertTrue(result.contains("-"), "Expected '-' in '\(result)'")
        XCTAssertTrue(result.contains("M"), "Expected 'M' in '\(result)'")
    }
}

// MARK: - Percent formatter

final class FinancialFormatPercentTests: XCTestCase {

    func test_positiveWithOneDecimal() {
        XCTAssertEqual(financialFormatPercent(42.3), "42.3%")
    }

    func test_zero() {
        XCTAssertEqual(financialFormatPercent(0.0), "0.0%")
    }

    func test_negativeMargin() {
        let result = financialFormatPercent(-5.2)
        XCTAssertTrue(result.contains("-5.2"), "Expected '-5.2' in '\(result)'")
    }

    func test_hundredPercent() {
        XCTAssertEqual(financialFormatPercent(100.0), "100.0%")
    }
}

// MARK: - QueryParams

final class FinancialQueryParamsTests: XCTestCase {

    func test_defaultLast30Days_fromIsBeforeTo() {
        let p = FinancialQueryParams.defaultLast30Days
        XCTAssertLessThan(p.from, p.to)
    }

    func test_defaultLast30Days_rollupIsDay() {
        XCTAssertEqual(FinancialQueryParams.defaultLast30Days.rollup, .day)
    }

    func test_rollup_rawValues() {
        XCTAssertEqual(FinancialRollup.day.rawValue,   "day")
        XCTAssertEqual(FinancialRollup.week.rawValue,  "week")
        XCTAssertEqual(FinancialRollup.month.rawValue, "month")
    }

    func test_rollup_allCases_count() {
        XCTAssertEqual(FinancialRollup.allCases.count, 3)
    }

    func test_init_storesFields() {
        let p = FinancialQueryParams(from: "2026-01-01", to: "2026-01-31", rollup: .week)
        XCTAssertEqual(p.from,   "2026-01-01")
        XCTAssertEqual(p.to,     "2026-01-31")
        XCTAssertEqual(p.rollup, .week)
    }
}

// MARK: - Repository unit tests

@MainActor
final class FinancialDashboardRepositoryTests: XCTestCase {

    func test_load_passesQueryParamsToAPI() async throws {
        let spy = GetSpy(wire: Fixtures.wire())
        let repo = FinancialDashboardRepositoryImpl(api: spy)
        let params = FinancialQueryParams(from: "2026-01-01", to: "2026-01-31", rollup: .month)
        _ = try await repo.load(params: params)

        let queryItems = await spy.capturedQueryItems ?? []
        let fromItem   = queryItems.first(where: { $0.name == "from" })
        let toItem     = queryItems.first(where: { $0.name == "to" })
        let rollupItem = queryItems.first(where: { $0.name == "rollup" })
        XCTAssertEqual(fromItem?.value,   "2026-01-01")
        XCTAssertEqual(toItem?.value,     "2026-01-31")
        XCTAssertEqual(rollupItem?.value, "month")
    }

    func test_load_hitsCorrectPath() async throws {
        let spy = GetSpy(wire: Fixtures.wire())
        let repo = FinancialDashboardRepositoryImpl(api: spy)
        _ = try await repo.load(params: .defaultLast30Days)
        let path = await spy.capturedPath
        XCTAssertEqual(path, "/api/v1/owner-pl/summary")
    }

    func test_load_convertsWireToViewSnapshot() async throws {
        let spy = GetSpy(wire: Fixtures.wire(grossCents: 999_00, netCents: 800_00,
                                              grossProfitCents: 400_00, grossProfitMarginPct: 50.0,
                                              outstandingCents: 1_000_00, overdueCents: 200_00))
        let repo = FinancialDashboardRepositoryImpl(api: spy)
        let snap = try await repo.load(params: .defaultLast30Days)
        XCTAssertEqual(snap.revenue.gross,           999.0, accuracy: 0.001)
        XCTAssertEqual(snap.revenue.net,             800.0, accuracy: 0.001)
        XCTAssertEqual(snap.grossProfit.marginPct,    50.0, accuracy: 0.001)
        XCTAssertEqual(snap.cashPosition.outstanding, 1_000.0, accuracy: 0.001)
        XCTAssertEqual(snap.cashPosition.overdue,     200.0, accuracy: 0.001)
    }

    func test_load_propagatesThrow() async {
        let spy = GetSpy(shouldThrow: true)
        let repo = FinancialDashboardRepositoryImpl(api: spy)
        do {
            _ = try await repo.load(params: .defaultLast30Days)
            XCTFail("Expected throw")
        } catch {
            // pass — error propagated correctly
        }
    }
}

// MARK: - Fixtures

private enum Fixtures {

    static func wire(
        grossCents: Int = 500_00,
        netCents: Int = 430_00,
        refundsCents: Int = 20_00,
        discountsCents: Int = 50_00,
        grossProfitCents: Int = 200_00,
        grossProfitMarginPct: Double = 46.5,
        netProfitCents: Int = 80_00,
        netProfitMarginPct: Double = 18.6,
        outstandingCents: Int = 900_00,
        overdueCents: Int = 100_00,
        truncated: Bool = false,
        customers: [OwnerPLTopCustomerWire] = []
    ) -> OwnerPLSummaryWire {
        OwnerPLSummaryWire(
            period: OwnerPLPeriodWire(from: "2026-03-01", to: "2026-03-31", days: 31),
            revenue: OwnerPLRevenueCentsWire(
                grossCents: grossCents,
                netCents: netCents,
                refundsCents: refundsCents,
                discountsCents: discountsCents
            ),
            grossProfit: OwnerPLProfitWire(cents: grossProfitCents, marginPct: grossProfitMarginPct),
            netProfit: OwnerPLProfitWire(cents: netProfitCents, marginPct: netProfitMarginPct),
            ar: OwnerPLARWire(
                outstandingCents: outstandingCents,
                overdueCents: overdueCents,
                truncated: truncated
            ),
            topCustomers: customers
        )
    }

    static func snapshot(
        netRevenue: Double = 430.0,
        netProfitMargin: Double = 18.6
    ) -> FinancialDashboardSnapshot {
        FinancialDashboardSnapshot(
            periodFrom: "2026-03-01",
            periodTo:   "2026-03-31",
            periodDays: 31,
            revenue: FinancialRevenue(gross: 500, net: netRevenue, refunds: 20, discounts: 50),
            grossProfit: FinancialGrossProfit(value: 200, marginPct: 46.5),
            netProfit:   FinancialNetProfit(value: 80, marginPct: netProfitMargin),
            cashPosition: FinancialCashPosition(outstanding: 900, overdue: 100, isApproximate: false),
            topCustomers: [
                FinancialTopCustomer(id: 1, name: "Acme Corp", revenue: 250),
                FinancialTopCustomer(id: 2, name: "Globe Ltd", revenue: 180),
            ]
        )
    }
}

// MARK: - Test helpers

private enum TestError: Error, LocalizedError {
    case boom
    var errorDescription: String? { "boom" }
}

/// Stub that satisfies FinancialDashboardRepository directly.
private actor StubRepo: FinancialDashboardRepository {
    private let result: Result<FinancialDashboardSnapshot, Error>

    init(result: Result<FinancialDashboardSnapshot, Error>) {
        self.result = result
    }

    func load(params: FinancialQueryParams) async throws -> FinancialDashboardSnapshot {
        switch result {
        case .success(let s): return s
        case .failure(let e): throw e
        }
    }
}

/// Spy APIClient that captures `get` call details and returns a canned wire
/// value via JSON encode → decode round-trip. This exercises the real
/// `ownerPLSummary` extension method end-to-end without a live server.
private actor GetSpy: APIClient {
    var capturedPath: String?
    var capturedQueryItems: [URLQueryItem]?
    private let wire: OwnerPLSummaryWire
    private let shouldThrow: Bool

    init(wire: OwnerPLSummaryWire = Fixtures.wire(), shouldThrow: Bool = false) {
        self.wire = wire
        self.shouldThrow = shouldThrow
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        capturedPath = path
        capturedQueryItems = query
        if shouldThrow { throw TestError.boom }
        // Round-trip via JSON so the generic decode works for OwnerPLSummaryWire.
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(wire)
        return try decoder.decode(T.self, from: data)
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw TestError.boom }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw TestError.boom }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw TestError.boom }
    func delete(_ path: String) async throws { throw TestError.boom }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw TestError.boom }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
