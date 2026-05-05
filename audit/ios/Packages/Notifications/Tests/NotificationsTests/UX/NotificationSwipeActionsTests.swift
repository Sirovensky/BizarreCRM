import Testing
import Foundation
@testable import Notifications
@testable import Networking

// MARK: - NotificationSwipeActionsTests

@Suite("NotificationSwipeActions")
@MainActor
struct NotificationSwipeActionsTests {

    // MARK: - NotificationSwipeActionState: flag toggle

    @Test("toggleFlag marks item as flagged")
    func toggleFlagOn() {
        let state = NotificationSwipeActionState()
        state.toggleFlag(id: 1, flagged: true)
        #expect(state.isFlagged(1))
    }

    @Test("toggleFlag unflags item")
    func toggleFlagOff() {
        let state = NotificationSwipeActionState()
        state.toggleFlag(id: 1, flagged: true)
        state.toggleFlag(id: 1, flagged: false)
        #expect(!state.isFlagged(1))
    }

    @Test("toggleFlag returns new flagged state")
    func toggleFlagReturnValue() {
        let state = NotificationSwipeActionState()
        let result = state.toggleFlag(id: 5, flagged: true)
        #expect(result == true)
    }

    @Test("toggleFlag false returns false")
    func toggleFlagFalseReturnValue() {
        let state = NotificationSwipeActionState()
        state.toggleFlag(id: 5, flagged: true)
        let result = state.toggleFlag(id: 5, flagged: false)
        #expect(result == false)
    }

    @Test("isFlagged false for unknown id")
    func isFlaggedUnknownId() {
        let state = NotificationSwipeActionState()
        #expect(!state.isFlagged(999))
    }

    @Test("toggling one id does not affect another")
    func flagIsIdSpecific() {
        let state = NotificationSwipeActionState()
        state.toggleFlag(id: 1, flagged: true)
        #expect(!state.isFlagged(2))
    }

    // MARK: - NotificationSwipeActionState: archive

    @Test("markArchived marks item archived")
    func markArchived() {
        let state = NotificationSwipeActionState()
        state.markArchived(1)
        #expect(state.isArchived(1))
    }

    @Test("removeArchived un-archives item")
    func removeArchived() {
        let state = NotificationSwipeActionState()
        state.markArchived(1)
        state.removeArchived(1)
        #expect(!state.isArchived(1))
    }

    @Test("isArchived false for unknown id")
    func isArchivedUnknown() {
        let state = NotificationSwipeActionState()
        #expect(!state.isArchived(42))
    }

    @Test("archiving one id does not archive another")
    func archiveIsIdSpecific() {
        let state = NotificationSwipeActionState()
        state.markArchived(1)
        #expect(!state.isArchived(2))
    }

    // MARK: - visibleItems filtering

    @Test("visibleItems returns all items when none archived")
    func visibleItemsAllVisible() {
        let state = NotificationSwipeActionState()
        let items = [makeItem(id: 1), makeItem(id: 2), makeItem(id: 3)]
        let visible = state.visibleItems(from: items)
        #expect(visible.count == 3)
    }

    @Test("visibleItems excludes archived items")
    func visibleItemsExcludesArchived() {
        let state = NotificationSwipeActionState()
        let items = [makeItem(id: 1), makeItem(id: 2), makeItem(id: 3)]
        state.markArchived(2)
        let visible = state.visibleItems(from: items)
        #expect(visible.count == 2)
        #expect(!visible.contains(where: { $0.id == 2 }))
    }

    @Test("visibleItems returns empty when all archived")
    func visibleItemsAllArchived() {
        let state = NotificationSwipeActionState()
        let items = [makeItem(id: 1), makeItem(id: 2)]
        state.markArchived(1)
        state.markArchived(2)
        let visible = state.visibleItems(from: items)
        #expect(visible.isEmpty)
    }

    @Test("visibleItems is immutable — original array unchanged")
    func visibleItemsImmutable() {
        let state = NotificationSwipeActionState()
        let items = [makeItem(id: 1), makeItem(id: 2)]
        state.markArchived(1)
        _ = state.visibleItems(from: items)
        // Original unchanged
        #expect(items.count == 2)
    }

    // MARK: - NotificationSwipeActionHandler: callbacks invoked

    @Test("markRead callback is called with correct id")
    func markReadCallbackCalled() async {
        var calledId: Int64? = nil
        let handler = NotificationSwipeActionHandler(
            markRead: { id in calledId = id },
            markUnread: { _ in },
            archive: { _ in },
            toggleFlag: { _, _ in }
        )
        await handler.markRead(7)
        #expect(calledId == 7)
    }

    @Test("markUnread callback is called with correct id")
    func markUnreadCallbackCalled() async {
        var calledId: Int64? = nil
        let handler = NotificationSwipeActionHandler(
            markRead: { _ in },
            markUnread: { id in calledId = id },
            archive: { _ in },
            toggleFlag: { _, _ in }
        )
        await handler.markUnread(3)
        #expect(calledId == 3)
    }

    @Test("archive callback is called with correct id")
    func archiveCallbackCalled() async {
        var calledId: Int64? = nil
        let handler = NotificationSwipeActionHandler(
            markRead: { _ in },
            markUnread: { _ in },
            archive: { id in calledId = id },
            toggleFlag: { _, _ in }
        )
        await handler.archive(9)
        #expect(calledId == 9)
    }

    @Test("toggleFlag callback is called with id and new value")
    func toggleFlagCallbackCalled() async {
        var calledId: Int64? = nil
        var calledFlagged: Bool? = nil
        let handler = NotificationSwipeActionHandler(
            markRead: { _ in },
            markUnread: { _ in },
            archive: { _ in },
            toggleFlag: { id, flag in calledId = id; calledFlagged = flag }
        )
        await handler.toggleFlag(12, true)
        #expect(calledId == 12)
        #expect(calledFlagged == true)
    }

    // MARK: - Helpers

    private func makeItem(id: Int64, isRead: Int = 0) -> NotificationItem {
        .init(
            id: id, type: "ticket", title: "T\(id)", message: nil,
            entityType: nil, entityId: nil, isRead: isRead, createdAt: nil
        )
    }
}
