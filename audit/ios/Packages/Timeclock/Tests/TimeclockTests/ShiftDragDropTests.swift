import XCTest
@testable import Timeclock
@testable import Networking

// §14.6 — iPad drag-drop shift reorder tests.
// Tests the pure local-reorder logic in ShiftSchedulePostViewModel.
// No network calls; uses the in-memory `sortedIndices` approach.

@MainActor
final class ShiftDragDropTests: XCTestCase {

    // MARK: - Helpers

    private func makeShift(id: Int64, employeeId: Int64 = 1, startAt: String) -> ScheduledShift {
        let end = startAt.replacingOccurrences(of: "T09", with: "T17")
        return ScheduledShift(id: id, employeeId: employeeId, startAt: startAt, endAt: end)
    }

    // MARK: - sortedShifts returns shifts in index order

    func test_sortedShifts_initialOrder_matchesLoadOrder() {
        let vm = ShiftSchedulePostViewModel(api: MinimalStubAPIClient())
        let shifts = [
            makeShift(id: 1, startAt: "2026-04-21T09:00:00Z"),
            makeShift(id: 2, startAt: "2026-04-22T09:00:00Z"),
            makeShift(id: 3, startAt: "2026-04-23T09:00:00Z"),
        ]
        vm._injectForTest(shifts: shifts)
        XCTAssertEqual(vm.sortedShifts.map(\.id), [1, 2, 3])
    }

    // MARK: - moveShifts reorders display order

    func test_moveShifts_movesFirstToLast() {
        let vm = ShiftSchedulePostViewModel(api: MinimalStubAPIClient())
        let shifts = [
            makeShift(id: 1, startAt: "2026-04-21T09:00:00Z"),
            makeShift(id: 2, startAt: "2026-04-22T09:00:00Z"),
            makeShift(id: 3, startAt: "2026-04-23T09:00:00Z"),
        ]
        vm._injectForTest(shifts: shifts)
        vm.moveShifts(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(vm.sortedShifts.map(\.id), [2, 3, 1])
    }

    func test_moveShifts_movesLastToFirst() {
        let vm = ShiftSchedulePostViewModel(api: MinimalStubAPIClient())
        let shifts = [
            makeShift(id: 1, startAt: "2026-04-21T09:00:00Z"),
            makeShift(id: 2, startAt: "2026-04-22T09:00:00Z"),
            makeShift(id: 3, startAt: "2026-04-23T09:00:00Z"),
        ]
        vm._injectForTest(shifts: shifts)
        vm.moveShifts(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(vm.sortedShifts.map(\.id), [3, 1, 2])
    }

    func test_moveShifts_swapsMiddle() {
        let vm = ShiftSchedulePostViewModel(api: MinimalStubAPIClient())
        let shifts = [
            makeShift(id: 10, startAt: "2026-04-21T09:00:00Z"),
            makeShift(id: 20, startAt: "2026-04-22T09:00:00Z"),
            makeShift(id: 30, startAt: "2026-04-23T09:00:00Z"),
            makeShift(id: 40, startAt: "2026-04-24T09:00:00Z"),
        ]
        vm._injectForTest(shifts: shifts)
        vm.moveShifts(fromOffsets: IndexSet(integer: 1), toOffset: 3)
        XCTAssertEqual(vm.sortedShifts.map(\.id), [10, 30, 20, 40])
    }

    func test_moveShifts_emptyList_isNoop() {
        let vm = ShiftSchedulePostViewModel(api: MinimalStubAPIClient())
        vm._injectForTest(shifts: [])
        vm.moveShifts(fromOffsets: IndexSet(), toOffset: 0)
        XCTAssertTrue(vm.sortedShifts.isEmpty)
    }

    func test_moveShifts_doesNotAffectUnderlyingShiftsArray() {
        let vm = ShiftSchedulePostViewModel(api: MinimalStubAPIClient())
        let shifts = [
            makeShift(id: 1, startAt: "2026-04-21T09:00:00Z"),
            makeShift(id: 2, startAt: "2026-04-22T09:00:00Z"),
        ]
        vm._injectForTest(shifts: shifts)
        vm.moveShifts(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        XCTAssertEqual(vm.sortedShifts.map(\.id), [2, 1])
        XCTAssertEqual(vm.shifts.map(\.id), [1, 2])
    }
}

// MARK: - Test helpers

extension ShiftSchedulePostViewModel {
    /// Inject shifts directly for unit testing (bypasses async network call).
    @MainActor
    func _injectForTest(shifts: [ScheduledShift]) {
        self.shifts = shifts
        self.sortedIndices = Array(shifts.indices)
    }
}

// MARK: - MinimalStubAPIClient (no network calls needed for drag-drop tests)

private actor MinimalStubAPIClient: APIClient {
    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw APITransportError.notImplemented
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
