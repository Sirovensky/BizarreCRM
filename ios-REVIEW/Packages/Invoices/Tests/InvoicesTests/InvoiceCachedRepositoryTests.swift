import XCTest
@testable import Invoices
import Networking
import Sync

// MARK: - InvoiceCachedRepositoryTests

/// Unit tests for `InvoiceCachedRepositoryImpl`.
/// Coverage: cache miss, cache hit, staleness, forceRefresh, invalidate.
final class InvoiceCachedRepositoryTests: XCTestCase {

    // MARK: - Cold read is stale

    func testColdReadIsStale() async throws {
        let api = SpyInvoiceAPIClient(invoices: [])
        let repo = InvoiceCachedRepositoryImpl(api: api)

        let result = try await repo.cachedList(filter: .all, keyword: nil, maxAgeSeconds: 300)

        XCTAssertTrue(result.isStale)
        XCTAssertNil(result.lastSyncedAt)
        XCTAssertTrue(result.value.isEmpty)
    }

    // MARK: - forceRefresh returns remote data

    func testForceRefreshPopulatesCache() async throws {
        let api = SpyInvoiceAPIClient(invoices: [sample(id: 1), sample(id: 2)])
        let repo = InvoiceCachedRepositoryImpl(api: api)

        let result = try await repo.forceRefresh(filter: .all, keyword: nil)

        XCTAssertEqual(result.value.count, 2)
        XCTAssertEqual(result.source, .remote)
        XCTAssertFalse(result.isStale)
        XCTAssertNotNil(result.lastSyncedAt)
    }

    // MARK: - Hot read after refresh is not stale

    func testHotReadAfterRefreshIsNotStale() async throws {
        let api = SpyInvoiceAPIClient(invoices: [sample(id: 1)])
        let repo = InvoiceCachedRepositoryImpl(api: api)

        _ = try await repo.forceRefresh(filter: .all, keyword: nil)
        let result = try await repo.cachedList(filter: .all, keyword: nil, maxAgeSeconds: 300)

        XCTAssertFalse(result.isStale)
        XCTAssertEqual(result.value.count, 1)
    }

    // MARK: - maxAgeSeconds=0 always stale

    func testMaxAge0AlwaysStale() async throws {
        let api = SpyInvoiceAPIClient(invoices: [sample(id: 1)])
        let repo = InvoiceCachedRepositoryImpl(api: api)

        _ = try await repo.forceRefresh(filter: .all, keyword: nil)
        let result = try await repo.cachedList(filter: .all, keyword: nil, maxAgeSeconds: 0)

        XCTAssertTrue(result.isStale)
    }

    // MARK: - Invalidate resets timestamp

    func testInvalidateMakesCacheStale() async throws {
        let api = SpyInvoiceAPIClient(invoices: [sample(id: 1)])
        let repo = InvoiceCachedRepositoryImpl(api: api)

        _ = try await repo.forceRefresh(filter: .all, keyword: nil)
        let hotResult = try await repo.cachedList(filter: .all, keyword: nil, maxAgeSeconds: 300)
        XCTAssertFalse(hotResult.isStale)

        await repo.invalidate(filter: .all, keyword: nil)

        let staleResult = try await repo.cachedList(filter: .all, keyword: nil, maxAgeSeconds: 300)
        XCTAssertTrue(staleResult.isStale)
    }

    // MARK: - lastSyncedAt updated after refresh

    func testLastSyncedAtUpdated() async throws {
        let api = SpyInvoiceAPIClient(invoices: [sample(id: 1)])
        let repo = InvoiceCachedRepositoryImpl(api: api)

        let before = await repo.lastSyncedAt
        XCTAssertNil(before)
        _ = try await repo.forceRefresh(filter: .all, keyword: nil)
        let after = await repo.lastSyncedAt
        XCTAssertNotNil(after)
    }

    // MARK: - Filter keys isolated

    func testFiltersHaveIsolatedCaches() async throws {
        let api = SpyInvoiceAPIClient(invoices: [sample(id: 1)])
        let repo = InvoiceCachedRepositoryImpl(api: api)

        _ = try await repo.forceRefresh(filter: .all, keyword: nil)

        // unpaid key is still cold.
        let result = try await repo.cachedList(filter: .unpaid, keyword: nil, maxAgeSeconds: 300)
        XCTAssertTrue(result.isStale)
    }

    // MARK: - Legacy list() delegates through cached path

    func testLegacyListDelegates() async throws {
        let api = SpyInvoiceAPIClient(invoices: [])
        let repo = InvoiceCachedRepositoryImpl(api: api)

        let items = try await repo.list(filter: .all, keyword: nil)
        XCTAssertTrue(items.isEmpty) // cold cache = empty
    }

    // MARK: - CachedResult source

    func testForceRefreshSourceIsRemote() async throws {
        let api = SpyInvoiceAPIClient(invoices: [sample(id: 1)])
        let repo = InvoiceCachedRepositoryImpl(api: api)

        let result = try await repo.forceRefresh(filter: .all, keyword: nil)
        XCTAssertEqual(result.source, .remote)
    }

    // MARK: - Helpers

    private func sample(id: Int64) -> InvoiceSummary {
        let json = """
        {"id":\(id),"order_id":"INV-\(id)","customer_id":1,"first_name":"Test","last_name":"Customer","total":100.0,"status":"paid","amount_due":0,"created_at":"2026-01-01"}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(InvoiceSummary.self, from: json)
    }
}

// MARK: - SpyInvoiceAPIClient

private actor SpyInvoiceAPIClient: APIClient {
    let invoices: [InvoiceSummary]

    init(invoices: [InvoiceSummary]) {
        self.invoices = invoices
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        guard path == "/api/v1/invoices" else { throw APITransportError.noBaseURL }
        // Build InvoicesListResponse via JSON since it's Decodable-only.
        let invoicesJson = invoices.map { inv in
            "{\"id\":\(inv.id),\"order_id\":\"\(inv.displayId)\",\"first_name\":\"Test\",\"last_name\":\"Customer\",\"total\":\(inv.total ?? 0),\"status\":\"\(inv.status ?? "paid")\",\"amount_due\":0,\"created_at\":\"2026-01-01\"}"
        }.joined(separator: ",")
        let responseJson = "{\"invoices\":[\(invoicesJson)]}".data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(InvoicesListResponse.self, from: responseJson)
        guard let cast = response as? T else { throw APITransportError.decoding("type mismatch") }
        return cast
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func delete(_ path: String) async throws {}

    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.noBaseURL
    }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
