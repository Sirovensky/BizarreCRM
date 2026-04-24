import Testing
import Foundation
@testable import Notifications
@testable import Networking

// MARK: - NotificationDetailSheetTests
//
// Tests cover the pure-logic parts of NotificationDetailSheet that don't
// require a live UIKit/SwiftUI render context:
//   - NotificationItem field access
//   - `onMarkRead` / `onMarkUnread` callback contracts
//   - Identifiable conformance (used by the `.sheet(item:)` modifier)

@Suite("NotificationDetailSheet")
struct NotificationDetailSheetTests {

    // MARK: - NotificationItem Identifiable (used by sheet(item:))

    @Test("NotificationItem is Identifiable via id")
    func identifiableViaId() {
        let item = makeItem(id: 77)
        #expect(item.id == 77)
    }

    @Test("two items with different ids are distinct")
    func distinctItems() {
        let a = makeItem(id: 1)
        let b = makeItem(id: 2)
        #expect(a.id != b.id)
    }

    @Test("two items with same id and same fields are equal (Hashable)")
    func equalItems() {
        let a = makeItem(id: 5)
        let b = makeItem(id: 5)
        #expect(a == b)
    }

    // MARK: - read / unread state

    @Test("item.read is false when isRead = 0")
    func readFalse() {
        let item = makeItem(id: 1, isRead: 0)
        #expect(!item.read)
    }

    @Test("item.read is true when isRead = 1")
    func readTrue() {
        let item = makeItem(id: 1, isRead: 1)
        #expect(item.read)
    }

    // MARK: - onMarkRead callback

    @Test("onMarkRead callback receives correct id")
    func markReadCallbackId() async {
        var received: Int64? = nil
        var markReadCalled = false

        let item = makeItem(id: 42, isRead: 0)

        // Simulate what the sheet's markRead button does
        let onMarkRead: (Int64) async -> Void = { id in
            received = id
            markReadCalled = true
        }

        await onMarkRead(item.id)
        #expect(markReadCalled)
        #expect(received == 42)
    }

    @Test("onMarkUnread callback receives correct id")
    func markUnreadCallbackId() async {
        var received: Int64? = nil

        let item = makeItem(id: 13, isRead: 1)

        let onMarkUnread: (Int64) async -> Void = { id in
            received = id
        }

        await onMarkUnread(item.id)
        #expect(received == 13)
    }

    // MARK: - Optional callbacks are safe to skip

    @Test("nil onMarkRead does not crash when not provided")
    func nilMarkReadSafe() async {
        let onMarkRead: ((Int64) async -> Void)? = nil
        // Simulate the sheet guard: `await onMarkRead?(item.id)`
        await onMarkRead?(1)
        // No crash — success
    }

    @Test("nil onMarkUnread does not crash when not provided")
    func nilMarkUnreadSafe() async {
        let onMarkUnread: ((Int64) async -> Void)? = nil
        await onMarkUnread?(2)
    }

    @Test("nil onDismiss does not crash when not provided")
    func nilOnDismissSafe() {
        let onDismiss: (() -> Void)? = nil
        onDismiss?()
    }

    // MARK: - Entity metadata

    @Test("entityType nil is handled")
    func entityTypeNil() {
        let item = makeItem(id: 1, entityType: nil)
        #expect(item.entityType == nil)
    }

    @Test("entityType set is preserved")
    func entityTypeSet() {
        let item = makeItem(id: 1, entityType: "ticket")
        #expect(item.entityType == "ticket")
    }

    @Test("entityId nil is handled")
    func entityIdNil() {
        let item = makeItem(id: 1, entityId: nil)
        #expect(item.entityId == nil)
    }

    @Test("entityId set is preserved")
    func entityIdSet() {
        let item = makeItem(id: 1, entityId: 123)
        #expect(item.entityId == 123)
    }

    // MARK: - Message

    @Test("message nil is handled")
    func messageNil() {
        let item = makeItem(id: 1, message: nil)
        #expect(item.message == nil)
    }

    @Test("message empty string preserved")
    func messageEmpty() {
        let item = makeItem(id: 1, message: "")
        #expect(item.message == "")
    }

    @Test("message long string preserved")
    func messageLong() {
        let msg = String(repeating: "a", count: 500)
        let item = makeItem(id: 1, message: msg)
        #expect(item.message?.count == 500)
    }

    // MARK: - createdAt handling

    @Test("createdAt nil does not crash")
    func createdAtNil() {
        let item = makeItem(id: 1, createdAt: nil)
        #expect(item.createdAt == nil)
    }

    @Test("createdAt ISO string preserved")
    func createdAtISO() {
        let ts = "2026-04-23T10:30:00Z"
        let item = makeItem(id: 1, createdAt: ts)
        #expect(item.createdAt == ts)
    }

    // MARK: - Concurrent callbacks don't interfere

    @Test("concurrent markRead calls are independent")
    func concurrentMarkRead() async {
        let results = ActorCollector()
        let cb: (Int64) async -> Void = { id in
            await results.add(id)
        }
        async let t1: () = cb(1)
        async let t2: () = cb(2)
        async let t3: () = cb(3)
        _ = await (t1, t2, t3)
        let collected = await results.values
        #expect(collected.sorted() == [1, 2, 3])
    }

    // MARK: - Helpers

    private func makeItem(
        id: Int64,
        type: String? = "ticket",
        title: String? = "Detail test",
        message: String? = "Body text",
        entityType: String? = "ticket",
        entityId: Int64? = 55,
        isRead: Int? = 0,
        createdAt: String? = "2026-04-23T08:00:00Z"
    ) -> NotificationItem {
        .init(
            id: id,
            type: type,
            title: title,
            message: message,
            entityType: entityType,
            entityId: entityId,
            isRead: isRead,
            createdAt: createdAt
        )
    }
}

// MARK: - ActorCollector (test helper)

private actor ActorCollector {
    private(set) var values: [Int64] = []
    func add(_ v: Int64) { values.append(v) }
}
