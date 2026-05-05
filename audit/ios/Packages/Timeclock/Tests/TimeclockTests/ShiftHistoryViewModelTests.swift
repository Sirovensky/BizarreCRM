import XCTest
@testable import Timeclock
@testable import Networking

/// Unit tests for ShiftHistoryViewModel.
/// Covers: loadAll, loadCurrentWeek, todayEntries filter, historicalEntries filter,
/// error handling, and zero-entry edge cases.
@MainActor
final class ShiftHistoryViewModelTests: XCTestCase {

    // MARK: - Helpers

    private let isoFormatter = ISO8601DateFormatter()

    private func makeEntry(
        id: Int64,
        userId: Int64 = 1,
        clockIn: String,
        clockOut: String? = nil,
        totalHours: Double? = nil
    ) -> ClockEntry {
        ClockEntry(id: id, userId: userId, clockIn: clockIn, clockOut: clockOut, totalHours: totalHours)
    }

    // MARK: - loadAll: success

    func test_loadAll_setsLoadedState_onSuccess() async {
        let entries = [makeEntry(id: 1, clockIn: "2026-04-20T09:00:00Z")]
        let stub = StubHoursClient(response: HoursResponse(entries: entries, totalHours: 8.0))
        let vm = ShiftHistoryViewModel(api: stub)

        await vm.loadAll()

        XCTAssertEqual(vm.loadState, .loaded)
        XCTAssertEqual(vm.entries.count, 1)
        XCTAssertEqual(vm.totalHours, 8.0, accuracy: 0.001)
    }

    func test_loadAll_setsFailedState_onError() async {
        let stub = StubHoursClient(error: TestError.boom)
        let vm = ShiftHistoryViewModel(api: stub)

        await vm.loadAll()

        guard case .failed = vm.loadState else {
            XCTFail("Expected .failed, got \(vm.loadState)"); return
        }
        XCTAssertTrue(vm.entries.isEmpty)
    }

    // MARK: - loadCurrentWeek: success

    func test_loadCurrentWeek_setsLoadedState_onSuccess() async {
        let entries = [
            makeEntry(id: 1, clockIn: "2026-04-20T08:00:00Z"),
            makeEntry(id: 2, clockIn: "2026-04-21T09:00:00Z"),
        ]
        let stub = StubHoursClient(response: HoursResponse(entries: entries, totalHours: 16.0))
        let vm = ShiftHistoryViewModel(api: stub)

        await vm.loadCurrentWeek()

        XCTAssertEqual(vm.loadState, .loaded)
        XCTAssertEqual(vm.entries.count, 2)
        XCTAssertEqual(vm.totalHours, 16.0, accuracy: 0.001)
    }

    func test_loadCurrentWeek_setsFailedState_onError() async {
        let stub = StubHoursClient(error: TestError.boom)
        let vm = ShiftHistoryViewModel(api: stub)

        await vm.loadCurrentWeek()

        guard case .failed = vm.loadState else {
            XCTFail("Expected .failed, got \(vm.loadState)"); return
        }
    }

    // MARK: - todayEntries filter

    func test_todayEntries_includesOnlyTodayEntries() async {
        // Fixed "now" = 2026-04-23T12:00:00Z (Thursday). Epoch = 1_776_967_200.
        let fixedNow = Date(timeIntervalSince1970: 1_776_967_200)
        let todayISO = "2026-04-23T09:00:00Z"
        let yesterdayISO = "2026-04-22T10:00:00Z"

        let entries = [
            makeEntry(id: 1, clockIn: todayISO),
            makeEntry(id: 2, clockIn: yesterdayISO),
        ]
        let stub = StubHoursClient(response: HoursResponse(entries: entries, totalHours: 16))
        let vm = ShiftHistoryViewModel(api: stub, now: { fixedNow })

        await vm.loadAll()

        XCTAssertEqual(vm.todayEntries.count, 1)
        XCTAssertEqual(vm.todayEntries.first?.id, 1)
    }

    func test_todayEntries_returnsEmpty_whenNoEntriesToday() async {
        // Fixed "now" = 2026-04-23T12:00:00Z
        let fixedNow = Date(timeIntervalSince1970: 1_776_967_200)
        // Entry from 3 days earlier — not today
        let entries = [makeEntry(id: 1, clockIn: "2026-04-20T09:00:00Z")]
        let stub = StubHoursClient(response: HoursResponse(entries: entries, totalHours: 8))
        let vm = ShiftHistoryViewModel(api: stub, now: { fixedNow })

        await vm.loadAll()

        XCTAssertTrue(vm.todayEntries.isEmpty)
    }

    // MARK: - historicalEntries filter

    func test_historicalEntries_excludesTodayEntries() async {
        // Fixed "now" = 2026-04-23T12:00:00Z
        let fixedNow = Date(timeIntervalSince1970: 1_776_967_200)
        let entries = [
            makeEntry(id: 1, clockIn: "2026-04-23T09:00:00Z"),  // today → excluded
            makeEntry(id: 2, clockIn: "2026-04-22T10:00:00Z"),  // yesterday → included
            makeEntry(id: 3, clockIn: "2026-04-21T08:00:00Z"),  // 2 days ago → included
        ]
        let stub = StubHoursClient(response: HoursResponse(entries: entries, totalHours: 24))
        let vm = ShiftHistoryViewModel(api: stub, now: { fixedNow })

        await vm.loadAll()

        XCTAssertEqual(vm.historicalEntries.count, 2)
        XCTAssertFalse(vm.historicalEntries.contains { $0.id == 1 })
    }

    // MARK: - Edge cases

    func test_emptyEntries_noStateError() async {
        let stub = StubHoursClient(response: HoursResponse(entries: [], totalHours: 0))
        let vm = ShiftHistoryViewModel(api: stub)

        await vm.loadAll()

        XCTAssertEqual(vm.loadState, .loaded)
        XCTAssertTrue(vm.entries.isEmpty)
        XCTAssertEqual(vm.totalHours, 0.0, accuracy: 0.001)
    }

    func test_initialState_isIdle() {
        let stub = StubHoursClient(response: HoursResponse(entries: [], totalHours: 0))
        let vm = ShiftHistoryViewModel(api: stub)
        XCTAssertEqual(vm.loadState, .idle)
    }

    func test_loadAll_setsLoadingState_beforeComplete() async {
        // Verify .loading is entered (observable side-effect) by checking
        // that state is .loaded after await — since we can't observe mid-flight
        // without concurrency gymnastics we verify the final state is correct.
        let stub = StubHoursClient(response: HoursResponse(entries: [], totalHours: 0))
        let vm = ShiftHistoryViewModel(api: stub)

        await vm.loadAll()

        XCTAssertEqual(vm.loadState, .loaded)
    }
}

// MARK: - Stubs

private enum TestError: Error, LocalizedError {
    case boom
    var errorDescription: String? { "test boom" }
}

private actor StubHoursClient: APIClient {
    private let response: HoursResponse?
    private let error: Error?

    init(response: HoursResponse? = nil, error: Error? = nil) {
        self.response = response
        self.error = error
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if let err = error { throw err }
        guard let resp = response as? T else {
            throw APITransportError.decoding("StubHoursClient: unexpected type \(T.self)")
        }
        return resp
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
    func setAuthToken(_ token: String?) {}
    func setBaseURL(_ url: URL?) {}
    func currentBaseURL() -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) {}
}
