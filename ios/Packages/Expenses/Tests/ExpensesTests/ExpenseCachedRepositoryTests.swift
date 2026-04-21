import XCTest
@testable import Expenses
@testable import Networking

// MARK: - Mock
// NOTE: MockAPIClient is already defined in ExpenseDetailViewModelTests.swift in this target.
// We define a separate actor scoped to list tests to avoid redeclaration.

actor MockExpenseListAPIClient: APIClient {
    enum Outcome {
        case success(ExpensesListResponse)
        case failure(Error)
    }

    var outcome: Outcome = .success(ExpensesListResponse(expenses: [], summary: nil))
    private(set) var callCount: Int = 0

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        guard path == "/api/v1/expenses" else { throw MockError.notConfigured }
        callCount += 1
        switch outcome {
        case .success(let resp):
            guard let cast = resp as? T else { throw MockError.typeMismatch }
            return cast
        case .failure(let err):
            throw err
        }
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw MockError.notConfigured }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw MockError.notConfigured }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw MockError.notConfigured }
    func delete(_ path: String) async throws { throw MockError.notConfigured }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw MockError.notConfigured }
    func setAuthToken(_ token: String?) {}
    func setBaseURL(_ url: URL?) {}
    func currentBaseURL() -> URL? { nil }
    func setRefresher(_ refresher: (any AuthSessionRefresher)?) {}

    func set(_ o: Outcome) { outcome = o }
}

// MARK: - Tests

final class ExpenseCachedRepositoryTests: XCTestCase {

    private static func makeResponse(count: Int = 1) -> ExpensesListResponse {
        let expenses = (1...count).map { i in
            Expense.fixture(id: Int64(i), category: "test", amount: Double(i))
        }
        return ExpensesListResponse(
            expenses: expenses,
            summary: ExpensesListResponse.Summary(totalAmount: Double(count), totalCount: count)
        )
    }

    func test_cacheHit_noSecondNetworkCall() async throws {
        let api = MockExpenseListAPIClient()
        await api.set(.success(Self.makeResponse()))
        let repo = ExpenseCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        _ = try await repo.listExpenses(keyword: nil)
        _ = try await repo.listExpenses(keyword: nil)

        let count = await api.callCount
        XCTAssertEqual(count, 1)
    }

    func test_expiredCache_refetches() async throws {
        let api = MockExpenseListAPIClient()
        await api.set(.success(Self.makeResponse()))
        let repo = ExpenseCachedRepositoryImpl(api: api, maxAgeSeconds: 0)

        _ = try await repo.listExpenses(keyword: nil)
        _ = try await repo.listExpenses(keyword: nil)

        let count = await api.callCount
        XCTAssertEqual(count, 2)
    }

    func test_differentKeywords_separateCacheEntries() async throws {
        let api = MockExpenseListAPIClient()
        await api.set(.success(Self.makeResponse()))
        let repo = ExpenseCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        _ = try await repo.listExpenses(keyword: nil)
        _ = try await repo.listExpenses(keyword: "coffee")

        let count = await api.callCount
        XCTAssertEqual(count, 2)
    }

    func test_forceRefresh_bypassesCache() async throws {
        let api = MockExpenseListAPIClient()
        await api.set(.success(Self.makeResponse()))
        let repo = ExpenseCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        _ = try await repo.listExpenses(keyword: nil)
        _ = try await repo.forceRefresh(keyword: nil)

        let count = await api.callCount
        XCTAssertEqual(count, 2)
    }

    func test_lastSyncedAt_nilBeforeFetch() async throws {
        let api = MockExpenseListAPIClient()
        let repo = ExpenseCachedRepositoryImpl(api: api, maxAgeSeconds: 300)
        let ts = await repo.lastSyncedAt
        XCTAssertNil(ts)
    }

    func test_lastSyncedAt_setAfterFetch() async throws {
        let api = MockExpenseListAPIClient()
        await api.set(.success(Self.makeResponse()))
        let repo = ExpenseCachedRepositoryImpl(api: api, maxAgeSeconds: 300)
        let before = Date()
        _ = try await repo.listExpenses(keyword: nil)
        let ts = await repo.lastSyncedAt
        XCTAssertNotNil(ts)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(ts), before)
    }

    func test_errorPropagates() async throws {
        let api = MockExpenseListAPIClient()
        await api.set(.failure(MockError.network))
        let repo = ExpenseCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        do {
            _ = try await repo.listExpenses(keyword: nil)
            XCTFail("Expected error")
        } catch { /* correct */ }
    }

    func test_summaryPreserved() async throws {
        let api = MockExpenseListAPIClient()
        let resp = Self.makeResponse(count: 5)
        await api.set(.success(resp))
        let repo = ExpenseCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        let result = try await repo.listExpenses(keyword: nil)
        XCTAssertEqual(result.expenses.count, 5)
        XCTAssertEqual(result.summary?.totalCount, 5)
    }
}
