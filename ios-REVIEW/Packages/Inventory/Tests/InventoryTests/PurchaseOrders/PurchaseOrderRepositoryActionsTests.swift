import XCTest
@testable import Inventory
@testable import Networking

// MARK: - PurchaseOrderRepositoryActionsTests
//
// Tests LivePurchaseOrderRepository against a stub APIClient,
// focusing on approve and cancel (the new status-transition actions).

final class PurchaseOrderRepositoryActionsTests: XCTestCase {

    // MARK: approve

    func test_approve_success_returnsPendingPO() async throws {
        let stub = POActionStubAPIClient(putResult: .success(MockPOFixtures.pending))
        let repo = LivePurchaseOrderRepository(api: stub)

        let result = try await repo.approve(id: 100)

        XCTAssertEqual(result.status, .pending)
        XCTAssertEqual(stub.lastPutPath, "/api/v1/inventory/purchase-orders/100")
    }

    func test_approve_networkError_throws() async {
        let stub = POActionStubAPIClient(putResult: .failure(APITransportError.noBaseURL))
        let repo = LivePurchaseOrderRepository(api: stub)

        await assertThrowsAsync(try await repo.approve(id: 100))
    }

    // MARK: cancel

    func test_cancel_success_returnsCancelledPO() async throws {
        let stub = POActionStubAPIClient(putResult: .success(MockPOFixtures.cancelled))
        let repo = LivePurchaseOrderRepository(api: stub)

        let result = try await repo.cancel(id: 100, reason: nil)

        XCTAssertEqual(result.status, .cancelled)
    }

    func test_cancel_withReason_usesCorrectPath() async throws {
        let stub = POActionStubAPIClient(putResult: .success(MockPOFixtures.cancelled))
        let repo = LivePurchaseOrderRepository(api: stub)

        _ = try await repo.cancel(id: 42, reason: "Supplier unavailable")

        XCTAssertEqual(stub.lastPutPath, "/api/v1/inventory/purchase-orders/42")
    }

    // MARK: list — verifies correct path

    func test_list_usesInventoryPath() async throws {
        let stub = POActionStubAPIClient(getResult: .success([MockPOFixtures.draft]))
        let repo = LivePurchaseOrderRepository(api: stub)

        _ = try await repo.list(status: nil)

        XCTAssertEqual(stub.lastGetPath, "/api/v1/inventory/purchase-orders/list")
    }

    // MARK: get — verifies correct path

    func test_get_usesInventoryPath() async throws {
        let stub = POActionStubAPIClient(getSingleResult: .success(MockPOFixtures.draft))
        let repo = LivePurchaseOrderRepository(api: stub)

        _ = try await repo.get(id: 77)

        XCTAssertEqual(stub.lastGetPath, "/api/v1/inventory/purchase-orders/77")
    }

    // MARK: create

    func test_create_usesInventoryPath() async throws {
        let stub = POActionStubAPIClient(postResult: .success(MockPOFixtures.draft))
        let repo = LivePurchaseOrderRepository(api: stub)
        let body = CreatePurchaseOrderRequest(
            supplierId: 1,
            expectedDate: nil,
            items: [],
            notes: nil
        )

        _ = try await repo.create(body)

        XCTAssertEqual(stub.lastPostPath, "/api/v1/inventory/purchase-orders")
    }
}

// MARK: - Helpers

private func assertThrowsAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #file,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {}
}

// MARK: - POActionStubAPIClient

private actor POActionStubAPIClient: APIClient {
    private(set) var lastGetPath: String?
    private(set) var lastPutPath: String?
    private(set) var lastPostPath: String?

    private let getResult: Result<[PurchaseOrder], Error>
    private let getSingleResult: Result<PurchaseOrder, Error>
    private let putResult: Result<PurchaseOrder, Error>
    private let postResult: Result<PurchaseOrder, Error>

    init(
        getResult: Result<[PurchaseOrder], Error> = .failure(APITransportError.noBaseURL),
        getSingleResult: Result<PurchaseOrder, Error> = .failure(APITransportError.noBaseURL),
        putResult: Result<PurchaseOrder, Error> = .failure(APITransportError.noBaseURL),
        postResult: Result<PurchaseOrder, Error> = .failure(APITransportError.noBaseURL)
    ) {
        self.getResult = getResult
        self.getSingleResult = getSingleResult
        self.putResult = putResult
        self.postResult = postResult
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        lastGetPath = path
        if path.contains("purchase-orders/list") {
            switch getResult {
            case .success(let pos):
                guard let result = pos as? T else { throw APITransportError.decoding("type mismatch") }
                return result
            case .failure(let e): throw e
            }
        } else if path.contains("purchase-orders/") {
            switch getSingleResult {
            case .success(let po):
                guard let result = po as? T else { throw APITransportError.decoding("type mismatch") }
                return result
            case .failure(let e): throw e
            }
        }
        throw APITransportError.noBaseURL
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        lastPutPath = path
        switch putResult {
        case .success(let po):
            guard let result = po as? T else { throw APITransportError.decoding("type mismatch") }
            return result
        case .failure(let e): throw e
        }
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        lastPostPath = path
        switch postResult {
        case .success(let po):
            guard let result = po as? T else { throw APITransportError.decoding("type mismatch") }
            return result
        case .failure(let e): throw e
        }
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
