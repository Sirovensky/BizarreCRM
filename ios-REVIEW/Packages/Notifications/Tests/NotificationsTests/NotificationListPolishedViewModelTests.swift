import Testing
import Foundation
@testable import Notifications
@testable import Networking

// MARK: - StubAPIClientPolished
// Separate stub so we don't conflict with StubAPIClient in NotificationListViewModelTests.

actor StubAPIClientPolished: APIClient {
    private let listResult: Result<[NotificationItem], Error>
    private let markReadResult: Result<NotificationItem, Error>
    private let markAllResult: Result<MarkAllReadResponse, Error>

    init(
        list: Result<[NotificationItem], Error> = .success([]),
        markRead: Result<NotificationItem, Error> = .success(
            .init(id: 0, type: nil, title: nil, message: nil,
                  entityType: nil, entityId: nil, isRead: 1, createdAt: nil)
        ),
        markAll: Result<MarkAllReadResponse, Error> = .success(.init(message: nil, updated: 0))
    ) {
        listResult = list
        markReadResult = markRead
        markAllResult = markAll
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        switch listResult {
        case .success(let rows):
            let response = NotificationsListResponse(notifications: rows)
            guard let cast = response as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        case .failure(let err): throw err
        }
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        switch markAllResult {
        case .success(let r):
            guard let cast = r as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        case .failure(let err): throw err
        }
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        switch markReadResult {
        case .success(let item):
            guard let cast = item as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        case .failure(let err): throw err
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

// MARK: - NotificationListPolishedViewModelTests

@Suite("NotificationListPolishedViewModel")
@MainActor
struct NotificationListPolishedViewModelTests {

    // MARK: Helpers

    static func makeItem(id: Int64, read: Bool, type: String = "ticket.updated") -> NotificationItem {
        .init(id: id, type: type, title: "T\(id)", message: "Msg",
              entityType: "ticket", entityId: id, isRead: read ? 1 : 0,
              createdAt: "2026-04-20T10:00:00Z")
    }

    // MARK: - Load

    @Test("load populates allItems on success")
    func loadPopulates() async {
        let api = StubAPIClientPolished(list: .success([makeItem(id: 1, read: false)]))
        let vm = NotificationListPolishedViewModel(api: api)
        await vm.load()
        #expect(vm.allItems.count == 1)
    }

    @Test("load sets errorMessage on failure")
    func loadSetsError() async {
        let api = StubAPIClientPolished(list: .failure(APITransportError.invalidResponse))
        let vm = NotificationListPolishedViewModel(api: api)
        await vm.load()
        #expect(vm.errorMessage != nil)
        #expect(vm.allItems.isEmpty)
    }

    @Test("isLoading is false after load")
    func isLoadingFalse() async {
        let api = StubAPIClientPolished(list: .success([]))
        let vm = NotificationListPolishedViewModel(api: api)
        await vm.load()
        #expect(!vm.isLoading)
    }

    // MARK: - Filter

    @Test("setFilter(.all) returns all items")
    func filterAll() async {
        let items = [makeItem(id: 1, read: false), makeItem(id: 2, read: true)]
        let api = StubAPIClientPolished(list: .success(items))
        let vm = NotificationListPolishedViewModel(api: api)
        await vm.load()
        vm.setFilter(.all)
        #expect(vm.filteredItems.count == 2)
    }

    @Test("setFilter(.unread) returns only unread items")
    func filterUnread() async {
        let items = [makeItem(id: 1, read: false), makeItem(id: 2, read: true)]
        let api = StubAPIClientPolished(list: .success(items))
        let vm = NotificationListPolishedViewModel(api: api)
        await vm.load()
        vm.setFilter(.unread)
        #expect(vm.filteredItems.count == 1)
        #expect(vm.filteredItems.first?.id == 1)
    }

    @Test("setFilter(.byType(.ticket)) returns only ticket items")
    func filterByTypeTicket() async {
        let items = [
            makeItem(id: 1, read: false, type: "ticket.updated"),
            makeItem(id: 2, read: false, type: "sms.inbound"),
        ]
        let api = StubAPIClientPolished(list: .success(items))
        let vm = NotificationListPolishedViewModel(api: api)
        await vm.load()
        vm.setFilter(.byType(.ticket))
        #expect(vm.filteredItems.count == 1)
        #expect(vm.filteredItems.first?.id == 1)
    }

    @Test("setFilter(.byType(.sms)) returns only SMS items")
    func filterByTypeSMS() async {
        let items = [
            makeItem(id: 1, read: false, type: "ticket.assigned"),
            makeItem(id: 2, read: false, type: "sms.inbound"),
            makeItem(id: 3, read: false, type: "sms.delivery_failed"),
        ]
        let api = StubAPIClientPolished(list: .success(items))
        let vm = NotificationListPolishedViewModel(api: api)
        await vm.load()
        vm.setFilter(.byType(.sms))
        #expect(vm.filteredItems.count == 2)
    }

    // MARK: - unreadCount

    @Test("unreadCount reflects items with read==false")
    func unreadCount() async {
        let items = [
            makeItem(id: 1, read: false),
            makeItem(id: 2, read: false),
            makeItem(id: 3, read: true),
        ]
        let api = StubAPIClientPolished(list: .success(items))
        let vm = NotificationListPolishedViewModel(api: api)
        await vm.load()
        #expect(vm.unreadCount == 2)
        #expect(vm.hasUnread)
    }

    // MARK: - Mark read

    @Test("markRead flips row optimistically")
    func markReadOptimistic() async {
        let item = makeItem(id: 5, read: false)
        let readItem = makeItem(id: 5, read: true)
        let api = StubAPIClientPolished(
            list: .success([item]),
            markRead: .success(readItem)
        )
        let vm = NotificationListPolishedViewModel(api: api)
        await vm.load()
        await vm.markRead(id: 5)
        #expect(vm.unreadCount == 0)
    }

    @Test("markRead reverts on server failure")
    func markReadReverts() async {
        let item = makeItem(id: 6, read: false)
        let api = StubAPIClientPolished(
            list: .success([item]),
            markRead: .failure(APITransportError.invalidResponse)
        )
        let vm = NotificationListPolishedViewModel(api: api)
        await vm.load()
        await vm.markRead(id: 6)
        #expect(vm.unreadCount == 1)
        #expect(vm.errorMessage != nil)
    }

    @Test("markRead on already-read item is a no-op")
    func markReadNoop() async {
        let item = makeItem(id: 7, read: true)
        let api = StubAPIClientPolished(list: .success([item]))
        let vm = NotificationListPolishedViewModel(api: api)
        await vm.load()
        await vm.markRead(id: 7) // should not crash or change anything
        #expect(vm.allItems.first?.read == true)
    }

    // MARK: - Mark all read

    @Test("markAllRead flips all items")
    func markAllRead() async {
        let items = [makeItem(id: 1, read: false), makeItem(id: 2, read: false)]
        let api = StubAPIClientPolished(
            list: .success(items),
            markAll: .success(.init(message: "ok", updated: 2))
        )
        let vm = NotificationListPolishedViewModel(api: api)
        await vm.load()
        await vm.markAllRead()
        #expect(vm.unreadCount == 0)
        #expect(vm.successBanner != nil)
    }

    @Test("markAllRead reverts on server failure")
    func markAllReadReverts() async {
        let items = [makeItem(id: 1, read: false), makeItem(id: 2, read: false)]
        let api = StubAPIClientPolished(
            list: .success(items),
            markAll: .failure(APITransportError.invalidResponse)
        )
        let vm = NotificationListPolishedViewModel(api: api)
        await vm.load()
        await vm.markAllRead()
        #expect(vm.unreadCount == 2)
        #expect(vm.errorMessage != nil)
    }

    // MARK: - Day sections

    @Test("daySections returns at least one section for non-empty items")
    func daySections() async {
        let item = makeItem(id: 1, read: false)
        let api = StubAPIClientPolished(list: .success([item]))
        let vm = NotificationListPolishedViewModel(api: api)
        await vm.load()
        #expect(!vm.daySections.isEmpty)
    }

    @Test("daySections respects active filter")
    func daySectionsFiltered() async {
        let items = [
            makeItem(id: 1, read: false, type: "ticket"),
            makeItem(id: 2, read: false, type: "sms"),
        ]
        let api = StubAPIClientPolished(list: .success(items))
        let vm = NotificationListPolishedViewModel(api: api)
        await vm.load()
        vm.setFilter(.byType(.ticket))
        let allSectionItems = vm.daySections.flatMap { $0.items }
        #expect(allSectionItems.allSatisfy { NotificationTypeFilter.ticket.matches($0.type) })
    }

    // MARK: - Banner dismiss

    @Test("dismissBanner clears successBanner")
    func dismissBanner() async {
        let items = [makeItem(id: 1, read: false)]
        let api = StubAPIClientPolished(
            list: .success(items),
            markAll: .success(.init(message: nil, updated: 1))
        )
        let vm = NotificationListPolishedViewModel(api: api)
        await vm.load()
        await vm.markAllRead()
        vm.dismissBanner()
        #expect(vm.successBanner == nil)
    }
}
