import XCTest
@testable import Timeclock
@testable import Networking

// MARK: - TimesheetListViewModelTests

@MainActor
final class TimesheetListViewModelTests: XCTestCase {

    // MARK: - Load: success

    func test_load_populatesEntries_onSuccess() async {
        let entries = [
            makeEntry(id: 1, clockIn: "2026-04-21T09:00:00Z", clockOut: "2026-04-21T17:00:00Z", totalHours: 8.0),
            makeEntry(id: 2, clockIn: "2026-04-22T09:00:00Z")
        ]
        let api = StubTimesheetAPI(entries: entries)
        let vm = TimesheetListViewModel(api: api, userIdProvider: { 42 })

        await vm.load()

        XCTAssertEqual(vm.loadState, .loaded)
        XCTAssertEqual(vm.entries.count, 2)
    }

    func test_load_setsLoadedState_onSuccess() async {
        let api = StubTimesheetAPI(entries: [])
        let vm = TimesheetListViewModel(api: api, userIdProvider: { 1 })

        await vm.load()

        XCTAssertEqual(vm.loadState, .loaded)
    }

    func test_load_setsFailedState_onError() async {
        let api = StubTimesheetAPI(listError: TestError.boom)
        let vm = TimesheetListViewModel(api: api, userIdProvider: { 1 })

        await vm.load()

        guard case .failed = vm.loadState else {
            XCTFail("Expected .failed, got \(vm.loadState)"); return
        }
        XCTAssertTrue(vm.entries.isEmpty)
    }

    // MARK: - Load: userId propagation

    func test_load_usesUserIdProvider_whenNoFilterUserId() async {
        let api = StubTimesheetAPI(entries: [])
        let vm = TimesheetListViewModel(api: api, userIdProvider: { 99 })
        // filterUserId not set — should use userIdProvider

        await vm.load()

        XCTAssertEqual(api.lastListUserId, 99)
    }

    func test_load_usesFilterUserId_whenSet() async {
        let api = StubTimesheetAPI(entries: [])
        let vm = TimesheetListViewModel(api: api, userIdProvider: { 1 })
        vm.filterUserId = 77

        await vm.load()

        XCTAssertEqual(api.lastListUserId, 77)
    }

    func test_load_passesDateFilters() async {
        let api = StubTimesheetAPI(entries: [])
        let vm = TimesheetListViewModel(api: api, userIdProvider: { 1 })
        vm.fromDate = "2026-04-01"
        vm.toDate   = "2026-04-30"

        await vm.load()

        XCTAssertEqual(api.lastFromDate, "2026-04-01")
        XCTAssertEqual(api.lastToDate,   "2026-04-30")
    }

    // MARK: - totalHours

    func test_totalHours_sumsEntriesWithNonNilHours() async {
        let entries = [
            makeEntry(id: 1, clockIn: "2026-04-21T09:00:00Z", totalHours: 4.5),
            makeEntry(id: 2, clockIn: "2026-04-22T09:00:00Z", totalHours: 3.0),
            makeEntry(id: 3, clockIn: "2026-04-23T09:00:00Z")   // no total_hours
        ]
        let api = StubTimesheetAPI(entries: entries)
        let vm = TimesheetListViewModel(api: api, userIdProvider: { 1 })
        await vm.load()

        XCTAssertEqual(vm.totalHours, 7.5, accuracy: 0.001)
    }

    func test_totalHours_isZero_whenNoEntries() async {
        let api = StubTimesheetAPI(entries: [])
        let vm = TimesheetListViewModel(api: api, userIdProvider: { 1 })
        await vm.load()

        XCTAssertEqual(vm.totalHours, 0)
    }

    // MARK: - editEntry: success

    func test_editEntry_updatesSavedEntry() async {
        let original = makeEntry(id: 10, clockIn: "2026-04-21T09:00:00Z", clockOut: "2026-04-21T17:00:00Z", totalHours: 8.0)
        let updated  = makeEntry(id: 10, clockIn: "2026-04-21T08:30:00Z", clockOut: "2026-04-21T17:00:00Z", totalHours: 8.5)
        let api = StubTimesheetAPI(entries: [original], editResult: updated)
        let vm = TimesheetListViewModel(api: api, userIdProvider: { 1 })
        await vm.load()

        await vm.editEntry(entryId: 10, clockIn: "2026-04-21T08:30:00Z", reason: "Corrected start time")

        XCTAssertEqual(vm.editState, .saved)
        let found = vm.entries.first { $0.id == 10 }
        XCTAssertEqual(found?.clockIn, "2026-04-21T08:30:00Z")
    }

    func test_editEntry_setsSavedState_onSuccess() async {
        let entry = makeEntry(id: 5, clockIn: "2026-04-20T09:00:00Z")
        let api = StubTimesheetAPI(entries: [entry], editResult: entry)
        let vm = TimesheetListViewModel(api: api, userIdProvider: { 1 })
        await vm.load()

        await vm.editEntry(entryId: 5, reason: "Adjusting notes")

        XCTAssertEqual(vm.editState, .saved)
    }

    func test_editEntry_setsFailedState_onError() async {
        let entry = makeEntry(id: 5, clockIn: "2026-04-20T09:00:00Z")
        let api = StubTimesheetAPI(entries: [entry], editError: TestError.boom)
        let vm = TimesheetListViewModel(api: api, userIdProvider: { 1 })
        await vm.load()

        await vm.editEntry(entryId: 5, reason: "Some reason")

        guard case .failed = vm.editState else {
            XCTFail("Expected .failed, got \(vm.editState)"); return
        }
    }

    // MARK: - editEntry: validation

    func test_editEntry_failsWithEmptyReason() async {
        let entry = makeEntry(id: 1, clockIn: "2026-04-21T09:00:00Z")
        let api = StubTimesheetAPI(entries: [entry])
        let vm = TimesheetListViewModel(api: api, userIdProvider: { 1 })
        await vm.load()

        await vm.editEntry(entryId: 1, reason: "   ")

        guard case .failed = vm.editState else {
            XCTFail("Expected .failed for blank reason, got \(vm.editState)"); return
        }
    }

    func test_editEntry_passesReasonToAPI() async {
        let entry = makeEntry(id: 3, clockIn: "2026-04-21T09:00:00Z")
        let api = StubTimesheetAPI(entries: [entry], editResult: entry)
        let vm = TimesheetListViewModel(api: api, userIdProvider: { 1 })
        await vm.load()

        await vm.editEntry(entryId: 3, reason: "Manager correction")

        XCTAssertEqual(api.lastEditReason, "Manager correction")
    }

    // MARK: - Immutability: entries array not mutated in place

    func test_editEntry_immutableUpdate_preservesOtherEntries() async {
        let e1 = makeEntry(id: 1, clockIn: "2026-04-20T09:00:00Z", totalHours: 8.0)
        let e2 = makeEntry(id: 2, clockIn: "2026-04-21T09:00:00Z", totalHours: 7.0)
        let updatedE1 = makeEntry(id: 1, clockIn: "2026-04-20T08:45:00Z", totalHours: 8.25)
        let api = StubTimesheetAPI(entries: [e1, e2], editResult: updatedE1)
        let vm = TimesheetListViewModel(api: api, userIdProvider: { 1 })
        await vm.load()

        await vm.editEntry(entryId: 1, reason: "Adjust clock-in")

        XCTAssertEqual(vm.entries.count, 2)
        XCTAssertEqual(vm.entries.first(where: { $0.id == 2 })?.totalHours, 7.0)
    }
}

// MARK: - Helpers

private func makeEntry(
    id: Int64,
    clockIn: String,
    clockOut: String? = nil,
    totalHours: Double? = nil
) -> ClockEntry {
    ClockEntry(id: id, userId: 1, clockIn: clockIn, clockOut: clockOut, totalHours: totalHours)
}

// MARK: - Stubs

private enum TestError: Error, LocalizedError {
    case boom
    var errorDescription: String? { "test boom" }
}

/// `@unchecked Sendable` — mutation only happens on the calling actor (tests are @MainActor).
private final class StubTimesheetAPI: APIClient, @unchecked Sendable {

    private let entries: [ClockEntry]
    private let listError: Error?
    private let editResult: ClockEntry?
    private let editError: Error?

    private(set) var lastListUserId: Int64?
    private(set) var lastFromDate: String?
    private(set) var lastToDate: String?
    private(set) var lastEditReason: String?

    init(
        entries: [ClockEntry],
        listError: Error? = nil,
        editResult: ClockEntry? = nil,
        editError: Error? = nil
    ) {
        self.entries = entries
        self.listError = listError
        self.editResult = editResult
        self.editError = editError
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if let err = listError { throw err }
        lastListUserId = query?.first(where: { $0.name == "user_id" }).flatMap { Int64($0.value ?? "") }
        lastFromDate   = query?.first(where: { $0.name == "from_date" })?.value
        lastToDate     = query?.first(where: { $0.name == "to_date" })?.value

        if let typed = entries as? T { return typed }
        throw APITransportError.decoding("Unexpected type \(T.self)")
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if let err = editError { throw err }
        if let encodable = body as? ClockEntryEditRequest {
            lastEditReason = encodable.reason
        }
        if let result = editResult as? T { return result }
        throw APITransportError.decoding("Unexpected type \(T.self)")
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.notImplemented
    }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
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
