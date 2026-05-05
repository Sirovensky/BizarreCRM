import XCTest
import GRDB
import Core
import Networking
@testable import Search

// MARK: - Mock APIClient

/// Minimal `APIClient` stub for ViewModel safety tests.
/// Defaults to throwing `URLError(.notConnectedToInternet)` so tests that
/// exercise the nil-ftsStore path don't require a live server.
private actor MockAPIClient: APIClient {
    enum Behaviour {
        case networkError
        case returnResults(GlobalSearchResults)
        case decodingError  // represented by returning a network error
    }

    var behaviour: Behaviour = .networkError

    func get<T: Decodable & Sendable>(
        _ path: String, query: [URLQueryItem]?, as type: T.Type
    ) async throws -> T {
        switch behaviour {
        case .networkError:
            throw URLError(.notConnectedToInternet)
        case .returnResults(let results):
            if let r = results as? T { return r }
            throw URLError(.badServerResponse)
        case .decodingError:
            throw URLError(.cannotDecodeContentData)
        }
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T { throw URLError(.notConnectedToInternet) }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T { throw URLError(.notConnectedToInternet) }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T { throw URLError(.notConnectedToInternet) }

    func delete(_ path: String) async throws { throw URLError(.notConnectedToInternet) }

    func getEnvelope<T: Decodable & Sendable>(
        _ path: String, query: [URLQueryItem]?, as type: T.Type
    ) async throws -> APIResponse<T> { throw URLError(.notConnectedToInternet) }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}

    func set(behaviour newBehaviour: Behaviour) {
        behaviour = newBehaviour
    }
}

// MARK: - GlobalSearchViewModelSafetyTests

/// Covers three crash-safety scenarios discovered in the iPad fresh-install crash:
///
///  1. Nil `FTSIndexStore` — `fetchLocal()` is a no-op; `scopeCounts` stays `.zero`.
///  2. API / network failure — `errorMessage` is set; app doesn't crash.
///  3. Empty remote results — `mergedRows` is empty; `scopeCounts` stays `.zero`.
@MainActor
final class GlobalSearchViewModelSafetyTests: XCTestCase {

    // MARK: - 1. Nil FTSIndexStore

    /// When `FTSIndexStore` is nil (the production default on fresh install),
    /// submitting a query must not crash and `scopeCounts` must stay `.zero`
    /// because `fetchLocal()` returns early via `guard let store = ftsStore`.
    func test_nilFTSStore_localPathIsNoop_scopeCountsRemainZero() async throws {
        let api = MockAPIClient()
        await api.set(behaviour: .returnResults(
            GlobalSearchResults(customers: [], tickets: [], inventory: [], invoices: [])
        ))

        let vm = GlobalSearchViewModel(api: api, ftsStore: nil)

        vm.onChange("iphone")
        // 300 ms debounce + network round trip. 800 ms is safe headroom.
        try await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertTrue(vm.localHits.isEmpty,
                      "localHits must be empty when ftsStore is nil")
        XCTAssertEqual(vm.scopeCounts, .zero,
                       "scopeCounts must be .zero when no local index is available")
        XCTAssertNil(vm.errorMessage,
                     "errorMessage must be nil when the API call succeeds")
    }

    // MARK: - 2. Remote network / decode failure

    /// When the API throws (network error, server 500, decode error, etc.),
    /// the ViewModel must set `errorMessage` and NOT crash.
    /// `mergedRows` must remain empty and `isLoading` must return to false.
    func test_apiFailure_setsErrorMessage_doesNotCrash() async throws {
        let api = MockAPIClient()
        await api.set(behaviour: .networkError)

        let vm = GlobalSearchViewModel(api: api, ftsStore: nil)

        vm.onChange("customer")
        try await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertNotNil(vm.errorMessage,
                        "errorMessage must be set when the API call fails")
        XCTAssertTrue(vm.mergedRows.isEmpty,
                      "mergedRows must be empty after an API failure with no local results")
        XCTAssertFalse(vm.isLoading,
                       "isLoading must be false after the fetch completes (even on error)")
    }

    // MARK: - 3. Empty remote results

    /// When the server returns all-empty arrays, `mergedRows` must be empty and
    /// `scopeCounts` must be `.zero`. No crash, no stale state from a previous query.
    func test_emptyRemoteResults_mergedRowsEmpty_scopeCountsZero() async throws {
        let api = MockAPIClient()
        await api.set(behaviour: .returnResults(
            GlobalSearchResults(customers: [], tickets: [], inventory: [], invoices: [])
        ))

        let vm = GlobalSearchViewModel(api: api, ftsStore: nil)

        vm.onChange("xyz-no-match")
        try await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertTrue(vm.mergedRows.isEmpty,
                      "mergedRows must be empty when server returns no results")
        XCTAssertEqual(vm.scopeCounts, .zero,
                       "scopeCounts must be .zero when server returns no results and ftsStore is nil")
        XCTAssertNil(vm.errorMessage,
                     "errorMessage must be nil when the fetch succeeds with empty results")
    }
}
