import XCTest
@testable import Inventory
@testable import Networking

final class PurchaseOrderRepositoryTests: XCTestCase {

    // MARK: - list

    func test_list_callsCorrectEndpoint() async throws {
        let stub = POStubAPIClient(listResult: .success([samplePO]))
        let repo = LivePurchaseOrderRepository(api: stub)
        let orders = try await repo.list(status: nil)
        XCTAssertEqual(orders.count, 1)
        XCTAssertEqual(orders.first?.id, 100)
    }

    func test_list_withStatus_propagatesParam() async throws {
        let stub = POStubAPIClient(listResult: .success([]))
        let repo = LivePurchaseOrderRepository(api: stub)
        let orders = try await repo.list(status: "open")
        XCTAssertEqual(orders.count, 0)
    }

    func test_list_networkError_throws() async {
        let stub = POStubAPIClient(listResult: .failure(APITransportError.noBaseURL))
        let repo = LivePurchaseOrderRepository(api: stub)
        await XCTAssertThrowsErrorAsync(try await repo.list(status: nil))
    }

    // MARK: - Helpers

    private var samplePO: PurchaseOrder {
        PurchaseOrder(
            id: 100,
            supplierId: 1,
            status: .draft,
            createdAt: Date(),
            items: [],
            totalCents: 0
        )
    }
}

// MARK: - XCTAssertThrowsErrorAsync helper

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #file,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch { }
}

// MARK: - POStubAPIClient

private actor POStubAPIClient: APIClient {
    enum StubError: Error { case unexpected }

    let listResult: Result<[PurchaseOrder], Error>

    init(listResult: Result<[PurchaseOrder], Error>) {
        self.listResult = listResult
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if path.contains("purchase-orders") {
            switch listResult {
            case .success(let pos):
                guard let result = pos as? T else { throw StubError.unexpected }
                return result
            case .failure(let e):
                throw e
            }
        }
        throw APITransportError.noBaseURL
    }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
