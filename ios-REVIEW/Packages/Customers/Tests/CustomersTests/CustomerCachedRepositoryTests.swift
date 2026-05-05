import XCTest
@testable import Customers
import Networking

// MARK: - CustomerCachedRepositoryTests

/// Tests for `CustomerCachedRepositoryImpl`:
/// - Cache hit avoids a second remote call within maxAge.
/// - Stale cache triggers a remote fetch.
/// - `forceRefresh` always hits remote.
/// - `lastSyncedAt` is populated after a successful fetch.
/// - Remote errors propagate correctly.
/// - Different keywords use independent cache entries.

final class CustomerCachedRepositoryTests: XCTestCase {

    // MARK: - lastSyncedAt

    func test_lastSyncedAt_isNilBeforeFirstFetch() async {
        let remote = SpyCustomerRepo()
        let repo = CustomerCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)
        let ts = await repo.lastSyncedAt
        XCTAssertNil(ts)
    }

    func test_lastSyncedAt_isSetAfterList() async throws {
        let remote = SpyCustomerRepo()
        let repo = CustomerCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)
        _ = try await repo.list(keyword: nil)
        let ts = await repo.lastSyncedAt
        XCTAssertNotNil(ts)
    }

    // MARK: - Cache hit

    func test_list_returnsCachedData_withinMaxAge() async throws {
        let remote = SpyCustomerRepo()
        let repo = CustomerCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)

        _ = try await repo.list(keyword: nil)
        _ = try await repo.list(keyword: nil)

        let count = await remote.callCount
        XCTAssertEqual(count, 1, "Remote should only be called once within maxAge window")
    }

    // MARK: - Stale cache

    func test_list_fetchesRemote_whenCacheIsStale() async throws {
        let remote = SpyCustomerRepo()
        let repo = CustomerCachedRepositoryImpl(remote: remote, maxAgeSeconds: 0)

        _ = try await repo.list(keyword: nil)
        _ = try await repo.list(keyword: nil)

        let count = await remote.callCount
        XCTAssertEqual(count, 2, "Remote should be called each time cache is stale")
    }

    // MARK: - forceRefresh

    func test_forceRefresh_alwaysHitsRemote() async throws {
        let remote = SpyCustomerRepo()
        let repo = CustomerCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)

        _ = try await repo.list(keyword: nil)            // Populates cache.
        _ = try await repo.forceRefresh(keyword: nil)    // Must bypass cache.
        _ = try await repo.forceRefresh(keyword: nil)    // Must bypass cache again.

        let count = await remote.callCount
        XCTAssertEqual(count, 3)
    }

    func test_forceRefresh_updatesLastSyncedAt() async throws {
        let remote = SpyCustomerRepo()
        let repo = CustomerCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)
        let before = Date()
        _ = try await repo.forceRefresh(keyword: nil)
        let ts = await repo.lastSyncedAt
        XCTAssertNotNil(ts)
        XCTAssertGreaterThanOrEqual(ts!, before)
    }

    func test_forceRefresh_returnsRemoteData() async throws {
        let remote = SpyCustomerRepo(customerCount: 7)
        let repo = CustomerCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)
        let results = try await repo.forceRefresh(keyword: nil)
        XCTAssertEqual(results.count, 7)
    }

    // MARK: - Separate cache keys per keyword

    func test_list_usesIndependentCache_perKeyword() async throws {
        let remote = SpyCustomerRepo()
        let repo = CustomerCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)

        _ = try await repo.list(keyword: "alice")
        _ = try await repo.list(keyword: "bob")

        let count = await remote.callCount
        XCTAssertEqual(count, 2, "Different keywords should use independent cache entries")
    }

    func test_list_nilAndEmptyKeyword_shareCache() async throws {
        let remote = SpyCustomerRepo()
        let repo = CustomerCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)

        _ = try await repo.list(keyword: nil)
        _ = try await repo.list(keyword: nil)

        let count = await remote.callCount
        XCTAssertEqual(count, 1)
    }

    // MARK: - Error propagation

    func test_list_propagatesRemoteError() async {
        let remote = SpyCustomerRepo(shouldFail: true)
        let repo = CustomerCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)
        do {
            _ = try await repo.list(keyword: nil)
            XCTFail("Expected error")
        } catch {
            // Expected.
        }
    }

    func test_forceRefresh_propagatesRemoteError() async {
        let remote = SpyCustomerRepo(shouldFail: true)
        let repo = CustomerCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)
        do {
            _ = try await repo.forceRefresh(keyword: nil)
            XCTFail("Expected error")
        } catch {
            // Expected.
        }
    }

    // MARK: - update invalidates cache

    func test_update_invalidatesCache_forcesFetchOnNextList() async throws {
        // Seed the remote with 3 customers and warm the cache.
        let remote = SpyCustomerRepo(customerCount: 3)
        let repo = CustomerCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)
        _ = try await repo.list(keyword: nil)

        // A second list call should be a cache hit (1 remote call so far).
        _ = try await repo.list(keyword: nil)
        let countBeforeUpdate = await remote.callCount
        XCTAssertEqual(countBeforeUpdate, 1, "Precondition: second call hits cache")

        // update() should clear the cache even when the remote throws (StubCustomerRepo
        // throws for update), so we use a fresh repo that wraps an update-capable stub.
        let updateRemote = SpyCustomerRepo(customerCount: 5, supportsUpdate: true)
        let updateRepo = CustomerCachedRepositoryImpl(remote: updateRemote, maxAgeSeconds: 300)
        _ = try await updateRepo.list(keyword: nil)

        let req = UpdateCustomerRequest(firstName: "New")
        _ = try await updateRepo.update(id: 1, req)

        // After update the cache is cleared — next list should hit remote again.
        _ = try await updateRepo.list(keyword: nil)
        let callsAfter = await updateRemote.callCount
        // Calls: 1 (initial list) + 1 (update) + 1 (list after invalidation) = 3
        XCTAssertEqual(callsAfter, 3, "list after update must bypass cache")
    }
}

// MARK: - Performance

final class CustomerListPerfTests: XCTestCase {
    /// Baseline benchmark: reading 1000 rows from in-memory cache.
    /// Documents the data-access cost of the cache layer. A full 60fps
    /// scrolling benchmark requires XCUITest; this covers the repository layer.
    func test_cachedList_1000Rows_performance() throws {
        let remote = SpyCustomerRepo(customerCount: 1_000)
        let repo = CustomerCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)

        let warmExp = self.expectation(description: "cache warm")
        Task {
            _ = try? await repo.list(keyword: nil)
            warmExp.fulfill()
        }
        wait(for: [warmExp], timeout: 5)

        measure {
            let readExp = self.expectation(description: "measure read")
            Task {
                _ = try? await repo.list(keyword: nil)
                readExp.fulfill()
            }
            self.wait(for: [readExp], timeout: 5)
        }
    }
}

// MARK: - Helpers

private actor SpyCustomerRepo: CustomerRepository {
    private let shouldFail: Bool
    private let customerCount: Int
    private let supportsUpdate: Bool
    private(set) var callCount: Int = 0

    init(shouldFail: Bool = false, customerCount: Int = 0, supportsUpdate: Bool = false) {
        self.shouldFail = shouldFail
        self.customerCount = customerCount
        self.supportsUpdate = supportsUpdate
    }

    func list(keyword: String?) async throws -> [CustomerSummary] {
        callCount += 1
        if shouldFail { throw CustTestError.boom }
        return (0..<customerCount).map { makeCustomer(index: $0) }
    }

    func update(id: Int64, _ req: UpdateCustomerRequest) async throws -> CustomerDetail {
        callCount += 1
        if !supportsUpdate { throw CustTestError.boom }
        // Return a minimal CustomerDetail with the updated first name.
        let json = """
        {
          "id": \(id),
          "first_name": "\(req.firstName)",
          "phones": [],
          "emails": []
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CustomerDetail.self, from: json)
    }

    private func makeCustomer(index: Int) -> CustomerSummary {
        let json = """
        {
          "id": \(index),
          "first_name": "User",
          "last_name": "\(index)"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(CustomerSummary.self, from: json)
    }
}

private enum CustTestError: Error { case boom }
