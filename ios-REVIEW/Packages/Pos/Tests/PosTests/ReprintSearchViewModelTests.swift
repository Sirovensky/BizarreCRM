import XCTest
@testable import Pos
import Networking

@MainActor
final class ReprintSearchViewModelTests: XCTestCase {

    // MARK: - Mock API

    private final class MockAPIClient: APIClient, @unchecked Sendable {
        var stubbedSummaries: [SaleSummary] = []
        var stubbedError: Error? = nil
        var lastQuery: [URLQueryItem]? = nil

        func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
            lastQuery = query
            if let error = stubbedError { throw error }
            if let result = stubbedSummaries as? T { return result }
            throw URLError(.badURL)
        }

        func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
            throw URLError(.badURL)
        }

        func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
            throw URLError(.badURL)
        }

        func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
            throw URLError(.badURL)
        }

        func delete(_ path: String) async throws {}

        func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
            throw URLError(.badURL)
        }

        func setAuthToken(_ token: String?) async {}
        func setBaseURL(_ url: URL?) async {}
        func currentBaseURL() async -> URL? { nil }
        func setRefresher(_ refresher: (any AuthSessionRefresher)?) async {}
    }

    private func makeSummaries() -> [SaleSummary] {
        [
            SaleSummary(id: 1, receiptNumber: "R-001", date: Date(), customerName: "Alice",  totalCents: 5000),
            SaleSummary(id: 2, receiptNumber: "R-002", date: Date(), customerName: "Bob",    totalCents: 12000),
        ]
    }

    // MARK: - Initial state

    func test_initialStateIsIdle() {
        let vm = ReprintSearchViewModel(api: MockAPIClient())
        XCTAssertEqual(vm.searchState, .idle)
        XCTAssertTrue(vm.query.isEmpty)
    }

    // MARK: - search() success

    func test_searchSuccessReturnsResults() async {
        let mock = MockAPIClient()
        mock.stubbedSummaries = makeSummaries()
        let vm = ReprintSearchViewModel(api: mock)
        vm.query = "Alice"
        vm.search()

        // Wait for async task
        await Task.yield()
        await Task.yield()

        if case .results(let results) = vm.searchState {
            XCTAssertEqual(results.count, 2)
        } else {
            // Give async more time
            try? await Task.sleep(for: .milliseconds(100))
            if case .results(let results) = vm.searchState {
                XCTAssertEqual(results.count, 2)
            } else {
                XCTFail("Expected .results, got \(vm.searchState)")
            }
        }
    }

    func test_searchPassesQueryParameter() async throws {
        let mock = MockAPIClient()
        mock.stubbedSummaries = makeSummaries()
        let vm = ReprintSearchViewModel(api: mock)
        vm.query = "Alice"
        vm.search()

        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(mock.lastQuery?.first?.value, "Alice")
    }

    // MARK: - search() empty results

    func test_searchEmptyResultsShowsEmptyResults() async throws {
        let mock = MockAPIClient()
        mock.stubbedSummaries = []
        let vm = ReprintSearchViewModel(api: mock)
        vm.query = "zzz"
        vm.search()

        try? await Task.sleep(for: .milliseconds(100))

        if case .results(let results) = vm.searchState {
            XCTAssertTrue(results.isEmpty)
        } else {
            XCTFail("Expected .results([]), got \(vm.searchState)")
        }
    }

    // MARK: - search() error

    func test_searchErrorSetsErrorState() async throws {
        let mock = MockAPIClient()
        mock.stubbedError = URLError(.notConnectedToInternet)
        let vm = ReprintSearchViewModel(api: mock)
        vm.query = "test"
        vm.search()

        try? await Task.sleep(for: .milliseconds(100))

        if case .error = vm.searchState {
            // pass
        } else {
            XCTFail("Expected .error, got \(vm.searchState)")
        }
    }

    // MARK: - search() with blank query

    func test_searchWithBlankQueryGoesIdle() {
        let vm = ReprintSearchViewModel(api: MockAPIClient())
        vm.query = "   "
        vm.search()
        XCTAssertEqual(vm.searchState, .idle)
    }

    // MARK: - clear()

    func test_clearResetsState() async throws {
        let mock = MockAPIClient()
        mock.stubbedSummaries = makeSummaries()
        let vm = ReprintSearchViewModel(api: mock)
        vm.query = "Alice"
        vm.search()
        try? await Task.sleep(for: .milliseconds(100))

        vm.clear()

        XCTAssertTrue(vm.query.isEmpty)
        XCTAssertEqual(vm.searchState, .idle)
    }
}
