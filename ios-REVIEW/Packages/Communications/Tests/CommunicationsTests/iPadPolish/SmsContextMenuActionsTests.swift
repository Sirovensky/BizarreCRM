import XCTest
@testable import Communications
@testable import Networking

// MARK: - SmsContextMenuActionsTests
//
// Tests that the ViewModel mutations triggered by context-menu actions
// behave correctly (optimistic updates, error handling).
// We load conversations through vm.load() to respect private(set) on .conversations.

final class SmsContextMenuActionsTests: XCTestCase {

    // MARK: - Fixture

    private func conv(
        phone: String = "+10005550001",
        unreadCount: Int = 0,
        isFlagged: Bool = false,
        isPinned: Bool = false,
        isArchived: Bool = false
    ) -> SmsConversation {
        SmsConversation(
            convPhone: phone,
            lastMessageAt: "2026-04-23T10:00:00Z",
            lastMessage: "Hi",
            lastDirection: "inbound",
            messageCount: 1,
            unreadCount: unreadCount,
            isFlagged: isFlagged,
            isPinned: isPinned,
            isArchived: isArchived
        )
    }

    /// Returns a vm pre-loaded with the given conversations.
    @MainActor
    private func loadedVM(conversations: [SmsConversation]) async -> SmsListViewModel {
        let stub = SimpleListStub(conversations: conversations)
        let vm = SmsListViewModel(repo: stub)
        await vm.load()
        return vm
    }

    // MARK: - markUnread (optimistic — local only)

    @MainActor
    func test_markUnread_bumpsBadgeCount_whenPreviouslyZero() async {
        let c = conv(unreadCount: 0)
        let vm = await loadedVM(conversations: [c])
        await vm.markUnread(phone: c.convPhone)

        let updated = vm.conversations.first { $0.convPhone == c.convPhone }
        XCTAssertEqual(updated?.unreadCount, 1)
    }

    @MainActor
    func test_markUnread_doesNotChangeBadge_whenAlreadyUnread() async {
        // Precondition: unreadCount > 0 — the predicate only bumps when == 0.
        let c = conv(unreadCount: 3)
        let vm = await loadedVM(conversations: [c])
        await vm.markUnread(phone: c.convPhone)

        let updated = vm.conversations.first { $0.convPhone == c.convPhone }
        XCTAssertEqual(updated?.unreadCount, 3)
    }

    @MainActor
    func test_markUnread_doesNotAffectOtherConversations() async {
        let c1 = conv(phone: "+1", unreadCount: 0)
        let c2 = conv(phone: "+2", unreadCount: 0)
        let vm = await loadedVM(conversations: [c1, c2])

        await vm.markUnread(phone: "+1")

        let c2After = vm.conversations.first { $0.convPhone == "+2" }
        XCTAssertEqual(c2After?.unreadCount, 0)
    }

    // MARK: - markRead (via ViewModel)

    @MainActor
    func test_markRead_zerosUnreadCountOptimistically() async {
        let c = conv(unreadCount: 5)
        let stub = MarkReadStub(conversations: [c])
        let vm = SmsListViewModel(repo: stub)
        await vm.load()
        await vm.markRead(phone: c.convPhone)

        let updated = vm.conversations.first { $0.convPhone == c.convPhone }
        XCTAssertEqual(updated?.unreadCount, 0)
    }

    // MARK: - toggleFlag optimistic update

    @MainActor
    func test_toggleFlag_flipsFlag() async {
        let c = conv(isFlagged: false)
        let stub = ToggleFlagStub(conversations: [c], result: true)
        let vm = SmsListViewModel(repo: stub)
        await vm.load()
        await vm.toggleFlag(phone: c.convPhone)

        let updated = vm.conversations.first { $0.convPhone == c.convPhone }
        XCTAssertTrue(updated?.isFlagged ?? false)
    }

    @MainActor
    func test_toggleFlag_setsActionError_onFailure() async {
        let c = conv(isFlagged: false)
        let stub = FailingStub(conversations: [c])
        let vm = SmsListViewModel(repo: stub)
        await vm.load()
        await vm.toggleFlag(phone: c.convPhone)

        XCTAssertNotNil(vm.actionError)
    }

    // MARK: - togglePin optimistic update

    @MainActor
    func test_togglePin_setsIsPinned() async {
        let c = conv(isPinned: false)
        let stub = TogglePinStub(conversations: [c], result: true)
        let vm = SmsListViewModel(repo: stub)
        await vm.load()
        await vm.togglePin(phone: c.convPhone)

        let updated = vm.conversations.first { $0.convPhone == c.convPhone }
        XCTAssertTrue(updated?.isPinned ?? false)
    }

    @MainActor
    func test_togglePin_pinnedConversationsFloatToTop() async {
        let c1 = conv(phone: "+1", isPinned: false)
        let c2 = conv(phone: "+2", isPinned: false)
        let stub = TogglePinStub(conversations: [c1, c2], result: true)
        let vm = SmsListViewModel(repo: stub)
        await vm.load()
        await vm.togglePin(phone: "+2")

        XCTAssertEqual(vm.conversations.first?.convPhone, "+2")
    }

    // MARK: - toggleArchive removes from list

    @MainActor
    func test_toggleArchive_removesConversationWhenArchiving() async {
        let c = conv(isArchived: false)
        let stub = ToggleArchiveStub(conversations: [c], result: true)
        let vm = SmsListViewModel(repo: stub)
        await vm.load()
        await vm.toggleArchive(phone: c.convPhone)

        XCTAssertTrue(vm.conversations.isEmpty)
    }

    // MARK: - clearActionError

    @MainActor
    func test_clearActionError_nilsTheError() async {
        let c = conv()
        let stub = FailingStub(conversations: [c])
        let vm = SmsListViewModel(repo: stub)
        await vm.load()
        await vm.toggleFlag(phone: c.convPhone)
        XCTAssertNotNil(vm.actionError)

        vm.clearActionError()
        XCTAssertNil(vm.actionError)
    }
}

// MARK: - Local stubs

private actor SimpleListStub: SmsRepository {
    let conversations: [SmsConversation]
    init(conversations: [SmsConversation]) { self.conversations = conversations }

    func listConversations(keyword: String?) async throws -> [SmsConversation] { conversations }
    func markRead(phone: String) async throws {}
    func toggleFlag(phone: String) async throws -> Bool { false }
    func togglePin(phone: String) async throws -> Bool { false }
    func toggleArchive(phone: String) async throws -> Bool { false }
}

private actor MarkReadStub: SmsRepository {
    let conversations: [SmsConversation]
    init(conversations: [SmsConversation]) { self.conversations = conversations }

    func listConversations(keyword: String?) async throws -> [SmsConversation] { conversations }
    func markRead(phone: String) async throws {}
    func toggleFlag(phone: String) async throws -> Bool { false }
    func togglePin(phone: String) async throws -> Bool { false }
    func toggleArchive(phone: String) async throws -> Bool { false }
}

private actor FailingStub: SmsRepository {
    let conversations: [SmsConversation]
    init(conversations: [SmsConversation]) { self.conversations = conversations }

    // listConversations succeeds so vm.load() populates .conversations
    func listConversations(keyword: String?) async throws -> [SmsConversation] { conversations }
    func markRead(phone: String) async throws { throw TestError.generic }
    func toggleFlag(phone: String) async throws -> Bool { throw TestError.generic }
    func togglePin(phone: String) async throws -> Bool { throw TestError.generic }
    func toggleArchive(phone: String) async throws -> Bool { throw TestError.generic }
}

private actor ToggleFlagStub: SmsRepository {
    let conversations: [SmsConversation]
    let result: Bool
    init(conversations: [SmsConversation], result: Bool) {
        self.conversations = conversations
        self.result = result
    }

    func listConversations(keyword: String?) async throws -> [SmsConversation] { conversations }
    func markRead(phone: String) async throws {}
    func toggleFlag(phone: String) async throws -> Bool { result }
    func togglePin(phone: String) async throws -> Bool { false }
    func toggleArchive(phone: String) async throws -> Bool { false }
}

private actor TogglePinStub: SmsRepository {
    let conversations: [SmsConversation]
    let result: Bool
    init(conversations: [SmsConversation], result: Bool) {
        self.conversations = conversations
        self.result = result
    }

    func listConversations(keyword: String?) async throws -> [SmsConversation] { conversations }
    func markRead(phone: String) async throws {}
    func toggleFlag(phone: String) async throws -> Bool { false }
    func togglePin(phone: String) async throws -> Bool { result }
    func toggleArchive(phone: String) async throws -> Bool { false }
}

private actor ToggleArchiveStub: SmsRepository {
    let conversations: [SmsConversation]
    let result: Bool
    init(conversations: [SmsConversation], result: Bool) {
        self.conversations = conversations
        self.result = result
    }

    func listConversations(keyword: String?) async throws -> [SmsConversation] { conversations }
    func markRead(phone: String) async throws {}
    func toggleFlag(phone: String) async throws -> Bool { false }
    func togglePin(phone: String) async throws -> Bool { false }
    func toggleArchive(phone: String) async throws -> Bool { result }
}

private enum TestError: Error { case generic }
