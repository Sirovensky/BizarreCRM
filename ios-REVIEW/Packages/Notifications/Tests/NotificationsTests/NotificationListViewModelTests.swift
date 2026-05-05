import XCTest
@testable import Notifications
@testable import Networking

/// Exercises the mark-read optimistic UI path — local flip first, server
/// round-trip second, revert on failure.
@MainActor
final class NotificationListViewModelTests: XCTestCase {

    func test_load_populatesItems() async {
        let api = StubAPIClient(listResult: .success([Self.sample(id: 1, read: false)]))
        let vm = NotificationListViewModel(api: api)
        await vm.load()
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.unreadCount, 1)
    }

    func test_load_surfacesServerError() async {
        let api = StubAPIClient(listResult: .failure(APITransportError.invalidResponse))
        let vm = NotificationListViewModel(api: api)
        await vm.load()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.items.isEmpty)
    }

    func test_markRead_flipsOptimisticallyAndPersists() async {
        let item = Self.sample(id: 42, read: false)
        let api = StubAPIClient(
            listResult: .success([item]),
            markReadResult: .success(Self.sample(id: 42, read: true))
        )
        let vm = NotificationListViewModel(api: api)
        await vm.load()
        XCTAssertEqual(vm.unreadCount, 1)

        await vm.markRead(id: 42)

        XCTAssertEqual(vm.unreadCount, 0)
        XCTAssertTrue(vm.items.first?.read ?? false)
    }

    func test_markRead_revertsOnServerFailure() async {
        let item = Self.sample(id: 7, read: false)
        let api = StubAPIClient(
            listResult: .success([item]),
            markReadResult: .failure(APITransportError.invalidResponse)
        )
        let vm = NotificationListViewModel(api: api)
        await vm.load()
        await vm.markRead(id: 7)

        // State reverted on failure.
        XCTAssertFalse(vm.items.first?.read ?? true, "Row must revert to unread when the server rejects")
        XCTAssertEqual(vm.unreadCount, 1)
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_markAllRead_flipsEveryRow() async {
        let items = [
            Self.sample(id: 1, read: false),
            Self.sample(id: 2, read: false),
            Self.sample(id: 3, read: true),
        ]
        let api = StubAPIClient(
            listResult: .success(items),
            markAllReadResult: .success(MarkAllReadResponse(message: "ok", updated: 2))
        )
        let vm = NotificationListViewModel(api: api)
        await vm.load()
        XCTAssertEqual(vm.unreadCount, 2)

        await vm.markAllRead()
        XCTAssertEqual(vm.unreadCount, 0)
        XCTAssertTrue(vm.items.allSatisfy { $0.read })
        XCTAssertNotNil(vm.successBanner)
    }

    // MARK: - Fixtures

    static func sample(id: Int64, read: Bool) -> NotificationItem {
        .init(
            id: id, type: "ticket.updated",
            title: "Ticket \(id)", message: "Body",
            entityType: "ticket", entityId: id,
            isRead: read ? 1 : 0,
            createdAt: "2026-04-20T12:00:00Z"
        )
    }
}

/// Hand-rolled stub that tracks only the methods the VM calls. The rest
/// throw so accidental extra calls in the code under test get caught.
actor StubAPIClient: APIClient {
    private let listResult: Result<[NotificationItem], Error>?
    private let markReadResult: Result<NotificationItem, Error>?
    private let markAllReadResult: Result<MarkAllReadResponse, Error>?

    init(
        listResult: Result<[NotificationItem], Error>? = nil,
        markReadResult: Result<NotificationItem, Error>? = nil,
        markAllReadResult: Result<MarkAllReadResponse, Error>? = nil
    ) {
        self.listResult = listResult
        self.markReadResult = markReadResult
        self.markAllReadResult = markAllReadResult
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        guard path == "/api/v1/notifications", let result = listResult else {
            throw APITransportError.noBaseURL
        }
        switch result {
        case .success(let rows):
            let response = NotificationsListResponse(notifications: rows)
            guard let cast = response as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        case .failure(let err):
            throw err
        }
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        guard path == "/api/v1/notifications/mark-all-read", let result = markAllReadResult else {
            throw APITransportError.noBaseURL
        }
        switch result {
        case .success(let resp):
            guard let cast = resp as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        case .failure(let err):
            throw err
        }
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        guard path.hasSuffix("/read"), let result = markReadResult else {
            throw APITransportError.noBaseURL
        }
        switch result {
        case .success(let item):
            guard let cast = item as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        case .failure(let err):
            throw err
        }
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
