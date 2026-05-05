import XCTest
@testable import Invoices
import Networking
import Sync

// MARK: - InvoiceListPerfTests

/// Phase-3 gate: every list must scroll 1000 rows at 60 fps+.
/// Measures the data-layer read path of `InvoiceCachedRepositoryImpl`.
final class InvoiceListPerfTests: XCTestCase {

    // MARK: - 1000-row hot-read benchmark

    func testCachedListHotRead1000Rows() async throws {
        let api = SpyInvoiceAPIClient1000()
        let repo = InvoiceCachedRepositoryImpl(api: api)

        // Populate cache.
        _ = try await repo.forceRefresh(filter: .all, keyword: nil)

        let start = Date()
        for _ in 0..<100 {
            let result = try await repo.cachedList(filter: .all, keyword: nil, maxAgeSeconds: 60)
            XCTAssertEqual(result.value.count, 1000)
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.0, "100 hot reads of 1000 rows took \(elapsed)s — exceeds 1s budget")
    }

    // MARK: - ViewModel fetch benchmark

    func testViewModelFetch1000Items() async throws {
        let api = SpyInvoiceAPIClient1000()
        let repo = InvoiceCachedRepositoryImpl(api: api)
        // Pre-warm.
        _ = try await repo.forceRefresh(filter: .all, keyword: nil)

        let vm = await InvoiceListViewModel(repo: repo)

        let start = Date()
        for _ in 0..<10 {
            await vm.load()
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 2.0, "10 VM loads took \(elapsed)s — exceeds 2s budget")

        let count = await vm.invoices.count
        XCTAssertEqual(count, 1000)
    }
}

// MARK: - SpyInvoiceAPIClient1000

private actor SpyInvoiceAPIClient1000: APIClient {

    private let response: InvoicesListResponse = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let invoicesJsonArray = (0..<1000).map { i in
            "{\"id\":\(i+1),\"order_id\":\"INV-\(i+1)\",\"first_name\":\"Customer\",\"last_name\":\"\(i)\",\"total\":\(Double(i)*10.5),\"status\":\"paid\",\"amount_due\":0,\"created_at\":\"2026-01-01\"}"
        }.joined(separator: ",")
        let responseJson = "{\"invoices\":[\(invoicesJsonArray)]}".data(using: .utf8)!
        return try! decoder.decode(InvoicesListResponse.self, from: responseJson)
    }()

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        guard path == "/api/v1/invoices" else { throw APITransportError.noBaseURL }
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
