import XCTest
@testable import Notifications
@testable import Networking

// MARK: - Mock (separate from StubAPIClient defined in NotificationListViewModelTests.swift)

actor MockNotifCachedAPIClient: APIClient {
    enum Outcome {
        case success([NotificationItem])
        case failure(Error)
    }

    var outcome: Outcome = .success([])
    private(set) var callCount: Int = 0

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        guard path == "/api/v1/notifications" else { throw APITransportError.noBaseURL }
        callCount += 1
        switch outcome {
        case .success(let rows):
            let response = NotificationsListResponse(notifications: rows)
            guard let cast = response as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        case .failure(let err):
            throw err
        }
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

    func set(_ o: Outcome) { outcome = o }
}

// MARK: - Fixture helper (separate from the one in NotificationListViewModelTests)

extension NotificationItem {
    static func cachedFixture(id: Int64 = 1) -> NotificationItem {
        .init(id: id, type: "ticket.updated", title: "Test \(id)", message: nil,
              entityType: "ticket", entityId: id, isRead: 0, createdAt: nil)
    }
}

// MARK: - Tests

final class NotificationCachedRepositoryTests: XCTestCase {

    func test_cacheHit_noSecondNetworkCall() async throws {
        let api = MockNotifCachedAPIClient()
        await api.set(.success([.cachedFixture()]))
        let repo = NotificationCachedRepositoryImpl(api: api, maxAgeSeconds: 120)

        _ = try await repo.listNotifications()
        _ = try await repo.listNotifications()

        let count = await api.callCount
        XCTAssertEqual(count, 1)
    }

    func test_expiredCache_refetches() async throws {
        let api = MockNotifCachedAPIClient()
        await api.set(.success([.cachedFixture()]))
        // maxAgeSeconds: -1 forces the cache to always be stale.
        let repo = NotificationCachedRepositoryImpl(api: api, maxAgeSeconds: -1)

        _ = try await repo.listNotifications()
        _ = try await repo.listNotifications()

        let count = await api.callCount
        XCTAssertEqual(count, 2)
    }

    func test_forceRefresh_bypassesCache() async throws {
        let api = MockNotifCachedAPIClient()
        await api.set(.success([.cachedFixture()]))
        let repo = NotificationCachedRepositoryImpl(api: api, maxAgeSeconds: 120)

        _ = try await repo.listNotifications()
        _ = try await repo.forceRefresh()

        let count = await api.callCount
        XCTAssertEqual(count, 2)
    }

    func test_lastSyncedAt_nilBeforeFetch() async throws {
        let api = MockNotifCachedAPIClient()
        let repo = NotificationCachedRepositoryImpl(api: api, maxAgeSeconds: 120)
        let ts = await repo.lastSyncedAt
        XCTAssertNil(ts)
    }

    func test_lastSyncedAt_setAfterFetch() async throws {
        let api = MockNotifCachedAPIClient()
        await api.set(.success([.cachedFixture()]))
        let repo = NotificationCachedRepositoryImpl(api: api, maxAgeSeconds: 120)
        let before = Date()
        _ = try await repo.listNotifications()
        let ts = await repo.lastSyncedAt
        XCTAssertNotNil(ts)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(ts), before)
    }

    func test_errorPropagates() async throws {
        let api = MockNotifCachedAPIClient()
        await api.set(.failure(APITransportError.noBaseURL))
        let repo = NotificationCachedRepositoryImpl(api: api, maxAgeSeconds: 120)

        do {
            _ = try await repo.listNotifications()
            XCTFail("Expected error")
        } catch { /* correct */ }
    }

    func test_returnsCorrectRows() async throws {
        let api = MockNotifCachedAPIClient()
        await api.set(.success([.cachedFixture(id: 55)]))
        let repo = NotificationCachedRepositoryImpl(api: api, maxAgeSeconds: 120)

        let rows = try await repo.listNotifications()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, 55)
    }
}
