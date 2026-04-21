import XCTest
@testable import Communications
@testable import Networking

// MARK: - Mock

actor MockSmsAPIClient: APIClient {
    enum Outcome {
        case success([SmsConversation])
        case failure(Error)
    }

    var outcome: Outcome = .success([])
    private(set) var callCount: Int = 0

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        guard path == "/api/v1/sms/conversations" else { throw APITransportError.noBaseURL }
        callCount += 1
        switch outcome {
        case .success(let rows):
            let response = SmsConversationsResponse(conversations: rows)
            guard let cast = response as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        case .failure(let err):
            throw err
        }
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws { throw APITransportError.noBaseURL }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}

    func set(_ o: Outcome) { outcome = o }
}

// MARK: - Fixture

extension SmsConversation {
    static func fixture(phone: String = "+10005550000") -> SmsConversation {
        let dict: [String: Any] = [
            "conv_phone": phone,
            "message_count": 1,
            "unread_count": 0,
            "is_flagged": false,
            "is_pinned": false
        ]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(SmsConversation.self, from: data)
    }
}

// MARK: - Tests

final class SmsCachedRepositoryTests: XCTestCase {

    func test_cacheHit_noSecondNetworkCall() async throws {
        let api = MockSmsAPIClient()
        await api.set(.success([.fixture()]))
        let repo = SmsCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        _ = try await repo.listConversations(keyword: nil)
        _ = try await repo.listConversations(keyword: nil)

        let count = await api.callCount
        XCTAssertEqual(count, 1)
    }

    func test_expiredCache_refetches() async throws {
        let api = MockSmsAPIClient()
        await api.set(.success([.fixture()]))
        let repo = SmsCachedRepositoryImpl(api: api, maxAgeSeconds: -1) // always stale

        _ = try await repo.listConversations(keyword: nil)
        _ = try await repo.listConversations(keyword: nil)

        let count = await api.callCount
        XCTAssertEqual(count, 2)
    }

    func test_differentKeywords_separateCacheEntries() async throws {
        let api = MockSmsAPIClient()
        await api.set(.success([.fixture()]))
        let repo = SmsCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        _ = try await repo.listConversations(keyword: nil)
        _ = try await repo.listConversations(keyword: "bob") // different key

        let count = await api.callCount
        XCTAssertEqual(count, 2)
    }

    func test_forceRefresh_bypassesCache() async throws {
        let api = MockSmsAPIClient()
        await api.set(.success([.fixture()]))
        let repo = SmsCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        _ = try await repo.listConversations(keyword: nil)
        _ = try await repo.forceRefresh(keyword: nil)

        let count = await api.callCount
        XCTAssertEqual(count, 2)
    }

    func test_lastSyncedAt_nilBeforeFetch() async throws {
        let api = MockSmsAPIClient()
        let repo = SmsCachedRepositoryImpl(api: api, maxAgeSeconds: 300)
        let ts = await repo.lastSyncedAt
        XCTAssertNil(ts)
    }

    func test_lastSyncedAt_setAfterFetch() async throws {
        let api = MockSmsAPIClient()
        await api.set(.success([.fixture()]))
        let repo = SmsCachedRepositoryImpl(api: api, maxAgeSeconds: 300)
        let before = Date()
        _ = try await repo.listConversations(keyword: nil)
        let ts = await repo.lastSyncedAt
        XCTAssertNotNil(ts)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(ts), before)
    }

    func test_errorPropagates() async throws {
        let api = MockSmsAPIClient()
        await api.set(.failure(APITransportError.noBaseURL))
        let repo = SmsCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        do {
            _ = try await repo.listConversations(keyword: nil)
            XCTFail("Expected error")
        } catch { /* correct */ }
    }

    func test_returnsCorrectRows() async throws {
        let api = MockSmsAPIClient()
        let conv = SmsConversation.fixture(phone: "+15555550001")
        await api.set(.success([conv]))
        let repo = SmsCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        let rows = try await repo.listConversations(keyword: nil)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.convPhone, "+15555550001")
    }
}
