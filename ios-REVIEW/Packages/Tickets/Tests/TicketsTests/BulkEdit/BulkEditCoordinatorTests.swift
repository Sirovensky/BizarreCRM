import XCTest
@testable import Tickets
@testable import Networking
import Foundation

// MARK: - StubBulkAPIClient

/// Minimal `APIClient` stub wired for `POST /api/v1/tickets/bulk-action`.
/// Replays a configurable `Result` so coordinator tests never hit the network.
actor StubBulkAPIClient: APIClient {

    // MARK: - Configuration

    var bulkResult: Result<BulkActionData, Error> = .success(
        BulkActionData(affected: 0, ticketIds: [])
    )

    // MARK: - Tracking

    var postCallCount: Int = 0
    var lastPostPath: String = ""
    var lastBulkBody: BulkActionRequest?

    // MARK: - APIClient stubs

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T {
        postCallCount += 1
        lastPostPath = path
        if let req = body as? BulkActionRequest {
            lastBulkBody = req
        }
        switch bulkResult {
        case .success(let data):
            guard let cast = data as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        case .failure(let error):
            throw error
        }
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T { throw APITransportError.noBaseURL }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T { throw APITransportError.noBaseURL }

    func delete(_ path: String) async throws {}

    func getEnvelope<T: Decodable & Sendable>(
        _ path: String, query: [URLQueryItem]?, as type: T.Type
    ) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

// MARK: - BulkEditCoordinatorTests

@MainActor
final class BulkEditCoordinatorTests: XCTestCase {

    // MARK: - Empty input

    func test_execute_emptyIDs_returnsEmptyArray() async {
        let stub = StubBulkAPIClient()
        let sut = BulkEditCoordinator(api: stub)
        let outcomes = await sut.execute(action: .changeStatus(statusId: 1), ticketIDs: [])
        XCTAssertTrue(outcomes.isEmpty)
        let callCount = await stub.postCallCount
        XCTAssertEqual(callCount, 0, "No network call expected for empty input")
    }

    // MARK: - All succeed

    func test_execute_allSucceed_whenServerReturnsAllIDs() async {
        let stub = StubBulkAPIClient()
        await stub.set(bulkResult: .success(BulkActionData(affected: 3, ticketIds: [1, 2, 3])))
        let sut = BulkEditCoordinator(api: stub)

        let outcomes = await sut.execute(action: .changeStatus(statusId: 5), ticketIDs: [1, 2, 3])

        XCTAssertEqual(outcomes.count, 3)
        XCTAssertTrue(outcomes.allSatisfy { $0.succeeded }, "All three should succeed")
    }

    // MARK: - Partial failure aggregation

    func test_execute_partialFailure_aggregatesCorrectly() async {
        let stub = StubBulkAPIClient()
        // Server only reports tickets 1 and 3 as affected; ticket 2 is missing.
        await stub.set(bulkResult: .success(BulkActionData(affected: 2, ticketIds: [1, 3])))
        let sut = BulkEditCoordinator(api: stub)

        let outcomes = await sut.execute(action: .reassign(userId: 99), ticketIDs: [1, 2, 3])

        XCTAssertEqual(outcomes.count, 3)

        let byId = Dictionary(uniqueKeysWithValues: outcomes.map { ($0.id, $0) })
        XCTAssertTrue(byId[1]!.succeeded)
        XCTAssertTrue(byId[3]!.succeeded)

        XCTAssertFalse(byId[2]!.succeeded)
        if case .failed(let msg) = byId[2]!.status {
            XCTAssertFalse(msg.isEmpty, "Failure message should be non-empty")
        } else {
            XCTFail("Expected .failed status for ticket 2")
        }
    }

    // MARK: - Total failure on network error

    func test_execute_networkError_allTicketsFail() async {
        let stub = StubBulkAPIClient()
        await stub.set(bulkResult: .failure(APITransportError.networkUnavailable))
        let sut = BulkEditCoordinator(api: stub)

        let outcomes = await sut.execute(action: .archive, ticketIDs: [10, 20, 30])

        XCTAssertEqual(outcomes.count, 3)
        XCTAssertTrue(outcomes.allSatisfy { !$0.succeeded }, "All should fail on network error")
        XCTAssertTrue(outcomes.allSatisfy {
            if case .failed(let msg) = $0.status { return !msg.isEmpty }
            return false
        })
    }

    // MARK: - Batch size enforcement

    func test_execute_over100IDs_failsWithoutNetworkCall() async {
        let stub = StubBulkAPIClient()
        let sut = BulkEditCoordinator(api: stub)
        let ids = Array(Int64(1)...Int64(101))

        let outcomes = await sut.execute(action: .changeStatus(statusId: 1), ticketIDs: ids)

        XCTAssertEqual(outcomes.count, 101)
        XCTAssertTrue(outcomes.allSatisfy { !$0.succeeded }, "All should fail when over limit")

        let callCount = await stub.postCallCount
        XCTAssertEqual(callCount, 0, "No network call should be made when batch exceeds limit")
    }

    // MARK: - Correct endpoint and action key

    func test_execute_postsToCorrectEndpoint() async {
        let stub = StubBulkAPIClient()
        await stub.set(bulkResult: .success(BulkActionData(affected: 1, ticketIds: [1])))
        let sut = BulkEditCoordinator(api: stub)

        _ = await sut.execute(action: .changeStatus(statusId: 7), ticketIDs: [1])

        let path = await stub.lastPostPath
        XCTAssertEqual(path, "/api/v1/tickets/bulk-action")
    }

    func test_execute_sendsCorrectActionKey_changeStatus() async {
        let stub = StubBulkAPIClient()
        await stub.set(bulkResult: .success(BulkActionData(affected: 1, ticketIds: [1])))
        let sut = BulkEditCoordinator(api: stub)

        _ = await sut.execute(action: .changeStatus(statusId: 7), ticketIDs: [1])

        let body = await stub.lastBulkBody
        XCTAssertEqual(body?.action, "change_status")
        XCTAssertEqual(body?.value, 7)
    }

    func test_execute_sendsCorrectActionKey_reassign() async {
        let stub = StubBulkAPIClient()
        await stub.set(bulkResult: .success(BulkActionData(affected: 1, ticketIds: [2])))
        let sut = BulkEditCoordinator(api: stub)

        _ = await sut.execute(action: .reassign(userId: 42), ticketIDs: [2])

        let body = await stub.lastBulkBody
        XCTAssertEqual(body?.action, "assign")
        XCTAssertEqual(body?.value, 42)
    }

    func test_execute_sendsCorrectActionKey_unassign() async {
        let stub = StubBulkAPIClient()
        await stub.set(bulkResult: .success(BulkActionData(affected: 1, ticketIds: [3])))
        let sut = BulkEditCoordinator(api: stub)

        _ = await sut.execute(action: .reassign(userId: nil), ticketIDs: [3])

        let body = await stub.lastBulkBody
        XCTAssertEqual(body?.action, "assign")
        XCTAssertNil(body?.value)
    }

    func test_execute_sendsCorrectActionKey_archive() async {
        let stub = StubBulkAPIClient()
        await stub.set(bulkResult: .success(BulkActionData(affected: 1, ticketIds: [5])))
        let sut = BulkEditCoordinator(api: stub)

        _ = await sut.execute(action: .archive, ticketIDs: [5])

        let body = await stub.lastBulkBody
        XCTAssertEqual(body?.action, "delete")
        XCTAssertNil(body?.value)
    }

    // MARK: - Progress state

    func test_execute_isLoadingFalseAfterCompletion() async {
        let stub = StubBulkAPIClient()
        await stub.set(bulkResult: .success(BulkActionData(affected: 1, ticketIds: [1])))
        let sut = BulkEditCoordinator(api: stub)

        _ = await sut.execute(action: .changeStatus(statusId: 1), ticketIDs: [1])

        XCTAssertFalse(sut.isLoading, "isLoading should be false after execute completes")
        XCTAssertEqual(sut.progress, 1.0, accuracy: 0.01)
    }

    // MARK: - Idempotency (two sequential calls)

    func test_execute_twoSequentialCalls_eachReturnsCorrectOutcomes() async {
        let stub = StubBulkAPIClient()
        await stub.set(bulkResult: .success(BulkActionData(affected: 2, ticketIds: [10, 11])))
        let sut = BulkEditCoordinator(api: stub)

        let first = await sut.execute(action: .changeStatus(statusId: 1), ticketIDs: [10, 11])
        let second = await sut.execute(action: .changeStatus(statusId: 2), ticketIDs: [10, 11])

        XCTAssertEqual(first.filter { $0.succeeded }.count, 2)
        XCTAssertEqual(second.filter { $0.succeeded }.count, 2)
        let callCount = await stub.postCallCount
        XCTAssertEqual(callCount, 2)
    }
}

// MARK: - StubBulkAPIClient mutation helpers (actor-isolated setters)

extension StubBulkAPIClient {
    func set(bulkResult: Result<BulkActionData, Error>) {
        self.bulkResult = bulkResult
    }
}
