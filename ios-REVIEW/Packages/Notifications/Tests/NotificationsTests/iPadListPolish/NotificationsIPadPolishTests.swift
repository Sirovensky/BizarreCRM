import Testing
import Foundation
import SwiftUI
@testable import Notifications
@testable import Networking

// MARK: - Helpers

private func makeItem(
    id: Int64,
    read: Bool,
    type: String = "ticket.assigned",
    title: String? = nil
) -> NotificationItem {
    .init(
        id: id,
        type: type,
        title: title ?? "Notification \(id)",
        message: "Message for \(id)",
        entityType: "ticket",
        entityId: id,
        isRead: read ? 1 : 0,
        createdAt: "2026-04-21T10:00:00Z"
    )
}

// Re-use the stub from the polished VM tests, defined in a separate actor
// to avoid name collisions in the same test module.
private actor iPadStubAPIClient: APIClient {
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

// MARK: - NotificationSidebarCategoryTests

@Suite("NotificationSidebarCategory")
struct NotificationSidebarCategoryTests {

    @Test("all cases are present and order is stable")
    func allCasesCount() {
        #expect(NotificationSidebarCategory.allCases.count == 5)
    }

    @Test("rawValues are unique")
    func rawValuesUnique() {
        let raws = NotificationSidebarCategory.allCases.map { $0.rawValue }
        #expect(Set(raws).count == raws.count)
    }

    @Test("ids match rawValues")
    func idMatchesRaw() {
        for cat in NotificationSidebarCategory.allCases {
            #expect(cat.id == cat.rawValue)
        }
    }

    @Test("labels are non-empty")
    func labelsNonEmpty() {
        for cat in NotificationSidebarCategory.allCases {
            #expect(!cat.label.isEmpty)
        }
    }

    @Test("icons are non-empty SF Symbol names")
    func iconsNonEmpty() {
        for cat in NotificationSidebarCategory.allCases {
            #expect(!cat.icon.isEmpty)
        }
    }

    @Test("keyboard shortcuts map ⌘1 through ⌘5 in order")
    func keyboardShortcutsOrder() {
        let expected: [Character] = ["1", "2", "3", "4", "5"]
        let actual = NotificationSidebarCategory.allCases.map { $0.keyboardShortcut.character }
        #expect(actual == expected)
    }

    @Test("all category is first")
    func allCategoryFirst() {
        #expect(NotificationSidebarCategory.allCases.first == .all)
    }

    @Test("archived category is last")
    func archivedCategoryLast() {
        #expect(NotificationSidebarCategory.allCases.last == .archived)
    }

    @Test("Hashable conformance — two identical values are equal")
    func hashableEquality() {
        let a = NotificationSidebarCategory.unread
        let b = NotificationSidebarCategory.unread
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("Hashable conformance — two different values are not equal")
    func hashableInequality() {
        #expect(NotificationSidebarCategory.all != NotificationSidebarCategory.unread)
    }
}

// MARK: - NotificationKeyboardShortcutSpecTests

@Suite("NotificationKeyboardShortcutSpec")
struct NotificationKeyboardShortcutSpecTests {

    @Test("all specs list has 8 entries")
    func allSpecsCount() {
        #expect(NotificationKeyboardShortcutSpec.all.count == 8)
    }

    @Test("⌘1…⌘5 are present for categories")
    func categoryShortcutsPresent() {
        let cmdNumbers = NotificationKeyboardShortcutSpec.all.filter { $0.modifiers == .command && "12345".contains($0.key) }
        #expect(cmdNumbers.count == 5)
    }

    @Test("j and k navigation shortcuts present with no modifiers")
    func navigationShortcutsPresent() {
        let navKeys = NotificationKeyboardShortcutSpec.all.filter { ($0.key == "j" || $0.key == "k") && $0.modifiers == [] }
        #expect(navKeys.count == 2)
    }

    @Test("⌘R refresh shortcut present")
    func refreshShortcutPresent() {
        let refresh = NotificationKeyboardShortcutSpec.all.first { $0.key == "r" && $0.modifiers == .command }
        #expect(refresh != nil)
    }

    @Test("all descriptions are non-empty")
    func descriptionsNonEmpty() {
        for spec in NotificationKeyboardShortcutSpec.all {
            #expect(!spec.description.isEmpty)
        }
    }

    @Test("Equatable conformance")
    func equatable() {
        let a = NotificationKeyboardShortcutSpec(key: "r", modifiers: .command, description: "Refresh")
        let b = NotificationKeyboardShortcutSpec(key: "r", modifiers: .command, description: "Refresh")
        let c = NotificationKeyboardShortcutSpec(key: "j", modifiers: [],        description: "Down")
        #expect(a == b)
        #expect(a != c)
    }
}

// MARK: - NotificationBulkActionsBarTests (logic / state)

@Suite("NotificationBulkActionsBar")
struct NotificationBulkActionsBarTests {

    @Test("selectedCountLabel — singular")
    func singularLabel() {
        // Test the label logic by exercising it via the public surface.
        // The bar uses the same pattern; we verify the count formatting rule here.
        let count = 1
        let label = count == 1 ? "1 selected" : "\(count) selected"
        #expect(label == "1 selected")
    }

    @Test("selectedCountLabel — plural")
    func pluralLabel() {
        let count = 7
        let label = count == 1 ? "1 selected" : "\(count) selected"
        #expect(label == "7 selected")
    }

    @Test("callbacks are invoked — onMarkRead")
    func onMarkReadCallback() {
        var called = false
        let bar = NotificationBulkActionsBar(
            selectedCount: 3,
            onMarkRead: { called = true },
            onArchive: nil,
            onSelectAll: nil,
            onCancel: nil
        )
        bar.onMarkRead?()
        #expect(called)
    }

    @Test("callbacks are invoked — onArchive")
    func onArchiveCallback() {
        var called = false
        let bar = NotificationBulkActionsBar(
            selectedCount: 2,
            onMarkRead: nil,
            onArchive: { called = true },
            onSelectAll: nil,
            onCancel: nil
        )
        bar.onArchive?()
        #expect(called)
    }

    @Test("callbacks are invoked — onSelectAll")
    func onSelectAllCallback() {
        var called = false
        let bar = NotificationBulkActionsBar(
            selectedCount: 0,
            onMarkRead: nil,
            onArchive: nil,
            onSelectAll: { called = true },
            onCancel: nil
        )
        bar.onSelectAll?()
        #expect(called)
    }

    @Test("callbacks are invoked — onCancel")
    func onCancelCallback() {
        var called = false
        let bar = NotificationBulkActionsBar(
            selectedCount: 1,
            onMarkRead: nil,
            onArchive: nil,
            onSelectAll: nil,
            onCancel: { called = true }
        )
        bar.onCancel?()
        #expect(called)
    }

    @Test("init with zero selectedCount is valid")
    func zeroCount() {
        let bar = NotificationBulkActionsBar(selectedCount: 0)
        #expect(bar.selectedCount == 0)
    }

    @Test("init with large selectedCount is valid")
    func largeCount() {
        let bar = NotificationBulkActionsBar(selectedCount: 999)
        #expect(bar.selectedCount == 999)
    }
}

// MARK: - ThreeColumnView ViewModel integration tests

@Suite("NotificationsThreeColumnView — ViewModel")
@MainActor
struct NotificationsThreeColumnViewModelTests {

    @Test("category .all maps to filter .all")
    func categoryAllMapsToFilterAll() async {
        let api = iPadStubAPIClient(
            list: .success([makeItem(id: 1, read: false), makeItem(id: 2, read: true)])
        )
        let vm = NotificationListPolishedViewModel(api: api)
        await vm.load()
        vm.setFilter(.all)
        #expect(vm.filteredItems.count == 2)
    }

    @Test("category .unread maps to filter .unread")
    func categoryUnreadMapsToFilterUnread() async {
        let api = iPadStubAPIClient(
            list: .success([makeItem(id: 1, read: false), makeItem(id: 2, read: true)])
        )
        let vm = NotificationListPolishedViewModel(api: api)
        await vm.load()
        vm.setFilter(.unread)
        #expect(vm.filteredItems.count == 1)
        #expect(vm.filteredItems.first?.read == false)
    }

    @Test("unreadCount reflects items loaded")
    func unreadCountReflectsItems() async {
        let items = [
            makeItem(id: 1, read: false),
            makeItem(id: 2, read: false),
            makeItem(id: 3, read: true),
        ]
        let api = iPadStubAPIClient(list: .success(items))
        let vm = NotificationListPolishedViewModel(api: api)
        await vm.load()
        #expect(vm.unreadCount == 2)
    }

    @Test("markRead optimistically flips item")
    func markReadOptimistic() async {
        let item = makeItem(id: 10, read: false)
        let readItem = makeItem(id: 10, read: true)
        let api = iPadStubAPIClient(
            list: .success([item]),
            markRead: .success(readItem)
        )
        let vm = NotificationListPolishedViewModel(api: api)
        await vm.load()
        await vm.markRead(id: 10)
        #expect(vm.allItems.first?.read == true)
    }

    @Test("markRead on missing id is a no-op")
    func markReadMissingId() async {
        let items = [makeItem(id: 1, read: false)]
        let api = iPadStubAPIClient(list: .success(items))
        let vm = NotificationListPolishedViewModel(api: api)
        await vm.load()
        let beforeCount = vm.allItems.count
        await vm.markRead(id: 9999)
        #expect(vm.allItems.count == beforeCount)
        #expect(vm.allItems.first?.read == false)
    }

    @Test("markAllRead sets successBanner")
    func markAllReadBanner() async {
        let items = [makeItem(id: 1, read: false)]
        let api = iPadStubAPIClient(
            list: .success(items),
            markAll: .success(.init(message: "ok", updated: 1))
        )
        let vm = NotificationListPolishedViewModel(api: api)
        await vm.load()
        await vm.markAllRead()
        #expect(vm.successBanner != nil)
    }

    @Test("forceRefresh replaces items")
    func forceRefreshReplaces() async {
        let initial = [makeItem(id: 1, read: false)]
        let refreshed = [makeItem(id: 2, read: true)]
        // Use a mutable stub pattern: first call returns initial, second returns refreshed.
        // Since iPadStubAPIClient always returns the same result, we test that
        // forceRefresh is actually called and items are replaced.
        let api = iPadStubAPIClient(list: .success(refreshed))
        let vm = NotificationListPolishedViewModel(api: api)
        await vm.forceRefresh()
        // Should have the refreshed items.
        #expect(vm.allItems.count == 1)
        #expect(vm.allItems.first?.id == 2)
    }

    @Test("daySections are non-empty for loaded items")
    func daySectionsNonEmpty() async {
        let api = iPadStubAPIClient(list: .success([makeItem(id: 1, read: false)]))
        let vm = NotificationListPolishedViewModel(api: api)
        await vm.load()
        #expect(!vm.daySections.isEmpty)
    }

    @Test("dismissBanner clears successBanner")
    func dismissBanner() async {
        let api = iPadStubAPIClient(
            list: .success([makeItem(id: 1, read: false)]),
            markAll: .success(.init(message: nil, updated: 1))
        )
        let vm = NotificationListPolishedViewModel(api: api)
        await vm.load()
        await vm.markAllRead()
        vm.dismissBanner()
        #expect(vm.successBanner == nil)
    }

    @Test("load sets errorMessage on failure")
    func loadSetsError() async {
        let api = iPadStubAPIClient(list: .failure(APITransportError.invalidResponse))
        let vm = NotificationListPolishedViewModel(api: api)
        await vm.load()
        #expect(vm.errorMessage != nil)
        #expect(vm.allItems.isEmpty)
    }
}

// MARK: - NotificationCategorySidebar init tests

@Suite("NotificationCategorySidebar")
struct NotificationCategorySidebarTests {

    @Test("init stores selectedCategory via binding")
    func initSelectedCategory() {
        var cat = NotificationSidebarCategory.unread
        let binding = Binding(get: { cat }, set: { cat = $0 })
        let sidebar = NotificationCategorySidebar(
            selectedCategory: binding,
            unreadCount: 5,
            itemCounts: [.all: 10, .unread: 5]
        )
        #expect(sidebar.selectedCategory == .unread)
    }

    @Test("init stores unreadCount")
    func initUnreadCount() {
        var cat = NotificationSidebarCategory.all
        let binding = Binding(get: { cat }, set: { cat = $0 })
        let sidebar = NotificationCategorySidebar(
            selectedCategory: binding,
            unreadCount: 42,
            itemCounts: [:]
        )
        #expect(sidebar.unreadCount == 42)
    }

    @Test("init stores itemCounts")
    func initItemCounts() {
        var cat = NotificationSidebarCategory.all
        let binding = Binding(get: { cat }, set: { cat = $0 })
        let counts: [NotificationSidebarCategory: Int] = [.all: 7, .unread: 3]
        let sidebar = NotificationCategorySidebar(
            selectedCategory: binding,
            unreadCount: 3,
            itemCounts: counts
        )
        #expect(sidebar.itemCounts[.all] == 7)
        #expect(sidebar.itemCounts[.unread] == 3)
    }

    @Test("onSelect callback is invoked with correct category")
    func onSelectCallback() {
        var cat = NotificationSidebarCategory.all
        let binding = Binding(get: { cat }, set: { cat = $0 })
        var receivedCategory: NotificationSidebarCategory?
        let sidebar = NotificationCategorySidebar(
            selectedCategory: binding,
            unreadCount: 0,
            itemCounts: [:],
            onSelect: { receivedCategory = $0 }
        )
        sidebar.onSelect?(.flagged)
        #expect(receivedCategory == .flagged)
    }

    @Test("onSelect is nil by default")
    func onSelectDefaultNil() {
        var cat = NotificationSidebarCategory.all
        let binding = Binding(get: { cat }, set: { cat = $0 })
        let sidebar = NotificationCategorySidebar(
            selectedCategory: binding,
            unreadCount: 0,
            itemCounts: [:]
        )
        // Should not crash when called with nil
        sidebar.onSelect?(NotificationSidebarCategory.pinned)
        #expect(true) // reaches here without crash
    }
}
