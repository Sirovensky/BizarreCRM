import XCTest
@testable import Inventory
import Networking

@MainActor
final class StocktakeListViewModelTests: XCTestCase {

    // MARK: - load success

    func test_load_success_populatesSessions() async {
        let sessions: [StocktakeSession] = [
            .init(id: 1, name: "Jan count", status: "open"),
            .init(id: 2, name: "Feb count", status: "committed"),
        ]
        let stub = StocktakeListStubAPIClient(sessions: sessions)
        let vm = StocktakeListViewModel(api: stub)
        await vm.load()
        XCTAssertEqual(vm.sessions.count, 2)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    func test_load_empty_noError() async {
        let stub = StocktakeListStubAPIClient(sessions: [])
        let vm = StocktakeListViewModel(api: stub)
        await vm.load()
        XCTAssertTrue(vm.sessions.isEmpty)
        XCTAssertNil(vm.errorMessage)
    }

    func test_load_failure_setsErrorMessage() async {
        let stub = StocktakeListStubAPIClient(sessions: [], shouldFail: true)
        let vm = StocktakeListViewModel(api: stub)
        await vm.load()
        XCTAssertTrue(vm.sessions.isEmpty)
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_load_withStatusFilter_passesFilter() async {
        let sessions: [StocktakeSession] = [
            .init(id: 1, name: "Open one", status: "open"),
        ]
        let stub = StocktakeListStubAPIClient(sessions: sessions)
        let vm = StocktakeListViewModel(api: stub)
        vm.statusFilter = "open"
        await vm.load()
        XCTAssertEqual(vm.sessions.count, 1)
        // Verify the stub received the filter
        let captured = await stub.capturedStatusFilter
        XCTAssertEqual(captured, "open")
    }

    func test_load_noDoubleLoad_whenAlreadyLoading() async {
        // Guard: isLoading == true prevents re-entry
        let stub = StocktakeListStubAPIClient(sessions: [])
        let vm = StocktakeListViewModel(api: stub)
        // Fire two concurrent loads; only one should go through
        async let a: Void = vm.load()
        async let b: Void = vm.load()
        _ = await (a, b)
        let callCount = await stub.listCallCount
        XCTAssertEqual(callCount, 1)
    }

    func test_load_reloadsAfterFirstComplete() async {
        let stub = StocktakeListStubAPIClient(sessions: [.init(id: 1, name: "X", status: "open")])
        let vm = StocktakeListViewModel(api: stub)
        await vm.load()
        await vm.load()
        let callCount = await stub.listCallCount
        XCTAssertEqual(callCount, 2)
    }

    func test_statusFilter_defaultIsNil() {
        let vm = StocktakeListViewModel(api: StocktakeListStubAPIClient(sessions: []))
        XCTAssertNil(vm.statusFilter)
    }
}

// MARK: - Stub

actor StocktakeListStubAPIClient: APIClient {
    private let stubbedSessions: [StocktakeSession]
    private let shouldFail: Bool
    private(set) var capturedStatusFilter: String? = nil
    private(set) var listCallCount: Int = 0

    init(sessions: [StocktakeSession], shouldFail: Bool = false) {
        self.stubbedSessions = sessions
        self.shouldFail = shouldFail
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if path == "/api/v1/stocktake" {
            listCallCount += 1
            capturedStatusFilter = query?.first(where: { $0.name == "status" })?.value
            if shouldFail { throw APITransportError.httpStatus(500, message: "Server error") }
            guard let result = stubbedSessions as? T else { throw APITransportError.decoding("type mismatch") }
            return result
        }
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if let s = stubbedSessions.first as? T { return s }
        if let r = CreatedResource(id: 1) as? T { return r }
        throw APITransportError.noBaseURL
    }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
