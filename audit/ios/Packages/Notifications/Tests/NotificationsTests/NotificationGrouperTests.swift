import XCTest
@testable import Notifications

final class NotificationGrouperTests: XCTestCase {

    // MARK: - Helpers

    private func item(
        id: String = UUID().uuidString,
        event: NotificationEvent = .ticketAssigned,
        title: String = "Test",
        receivedAt: Date,
        priority: NotificationPriority? = nil
    ) -> GroupableNotification {
        GroupableNotification(
            id: id,
            event: event,
            title: title,
            body: "body",
            receivedAt: receivedAt,
            priority: priority
        )
    }

    private let base = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Empty input

    func test_group_empty_returnsEmpty() {
        let result = NotificationGrouper.group([])
        XCTAssertTrue(result.bundles.isEmpty)
        XCTAssertTrue(result.singletons.isEmpty)
    }

    // MARK: - Single item → singleton

    func test_group_singleItem_returnsSingleton() {
        let i = item(receivedAt: base)
        let result = NotificationGrouper.group([i])
        XCTAssertTrue(result.bundles.isEmpty)
        XCTAssertEqual(result.singletons.count, 1)
        XCTAssertEqual(result.singletons.first?.id, i.id)
    }

    // MARK: - Two same-category items within window → bundle

    func test_group_twoSameCategory_withinWindow_bundled() {
        let i1 = item(id: "a", event: .ticketAssigned, receivedAt: base)
        let i2 = item(id: "b", event: .ticketAssigned, receivedAt: base.addingTimeInterval(10))
        let result = NotificationGrouper.group([i1, i2], windowSeconds: 30)
        XCTAssertEqual(result.bundles.count, 1)
        XCTAssertEqual(result.bundles[0].count, 2)
        XCTAssertTrue(result.singletons.isEmpty)
    }

    // MARK: - Two same-category items outside window → singletons

    func test_group_twoSameCategory_outsideWindow_singletons() {
        let i1 = item(id: "a", event: .ticketAssigned, receivedAt: base)
        let i2 = item(id: "b", event: .ticketAssigned, receivedAt: base.addingTimeInterval(60))
        let result = NotificationGrouper.group([i1, i2], windowSeconds: 30)
        XCTAssertTrue(result.bundles.isEmpty)
        XCTAssertEqual(result.singletons.count, 2)
    }

    // MARK: - Different categories → separate bundles

    func test_group_differentCategories_separateBundles() {
        let t1 = item(id: "t1", event: .ticketAssigned, receivedAt: base)
        let t2 = item(id: "t2", event: .ticketStatusChangeMine, receivedAt: base.addingTimeInterval(5))
        let s1 = item(id: "s1", event: .smsInbound, receivedAt: base.addingTimeInterval(2))
        let s2 = item(id: "s2", event: .smsInbound, receivedAt: base.addingTimeInterval(8))

        let result = NotificationGrouper.group([t1, t2, s1, s2], windowSeconds: 30)
        XCTAssertEqual(result.bundles.count, 2)
        XCTAssertTrue(result.singletons.isEmpty)
    }

    // MARK: - Critical items never bundled

    func test_group_criticalItem_neverBundled() {
        let c1 = item(id: "c1", event: .backupFailed, receivedAt: base, priority: .critical)
        let c2 = item(id: "c2", event: .backupFailed, receivedAt: base.addingTimeInterval(5), priority: .critical)
        let result = NotificationGrouper.group([c1, c2], windowSeconds: 30)
        XCTAssertTrue(result.bundles.isEmpty)
        XCTAssertEqual(result.singletons.count, 2)
    }

    // MARK: - Critical mixed with normal → critical stays singleton

    func test_group_criticalAmongNormal_criticalSingleton() {
        let normal1 = item(id: "n1", event: .ticketAssigned, receivedAt: base)
        let normal2 = item(id: "n2", event: .ticketAssigned, receivedAt: base.addingTimeInterval(5))
        let crit = item(id: "c1", event: .backupFailed, receivedAt: base.addingTimeInterval(2), priority: .critical)

        let result = NotificationGrouper.group([normal1, normal2, crit], windowSeconds: 30)
        // normals bundle; critical is singleton
        XCTAssertEqual(result.bundles.count, 1)
        XCTAssertEqual(result.bundles[0].count, 2)
        XCTAssertEqual(result.singletons.count, 1)
        XCTAssertEqual(result.singletons.first?.id, "c1")
    }

    // MARK: - minGroupSize respected

    func test_group_belowMinGroupSize_singleton() {
        let i1 = item(id: "a", event: .ticketAssigned, receivedAt: base)
        let result = NotificationGrouper.group([i1], windowSeconds: 30, minGroupSize: 3)
        XCTAssertTrue(result.bundles.isEmpty)
        XCTAssertEqual(result.singletons.count, 1)
    }

    func test_group_exactlyMinGroupSize_bundled() {
        let items = (0..<3).map { i in
            self.item(id: "i\(i)", event: .ticketAssigned, receivedAt: base.addingTimeInterval(Double(i) * 5))
        }
        let result = NotificationGrouper.group(items, windowSeconds: 30, minGroupSize: 3)
        XCTAssertEqual(result.bundles.count, 1)
        XCTAssertEqual(result.bundles[0].count, 3)
    }

    // MARK: - Bundle category is correct

    func test_group_bundleCategory_matchesItems() {
        let i1 = item(id: "a", event: .smsInbound, receivedAt: base)
        let i2 = item(id: "b", event: .smsInbound, receivedAt: base.addingTimeInterval(10))
        let result = NotificationGrouper.group([i1, i2])
        XCTAssertEqual(result.bundles.first?.category, .communications)
    }

    // MARK: - No duplicate processing

    func test_group_noItemProcessedTwice() {
        let items = (0..<5).map { i in
            self.item(id: "i\(i)", event: .ticketAssigned, receivedAt: base.addingTimeInterval(Double(i) * 5))
        }
        let result = NotificationGrouper.group(items, windowSeconds: 60)
        let bundleTotal = result.bundles.reduce(0) { $0 + $1.count }
        XCTAssertEqual(bundleTotal + result.singletons.count, items.count)
    }

    // MARK: - Bundle latestAt is newest item

    func test_group_bundleLatestAt_isNewest() {
        let newer = item(id: "a", event: .ticketAssigned, receivedAt: base.addingTimeInterval(20))
        let older = item(id: "b", event: .ticketAssigned, receivedAt: base)
        let result = NotificationGrouper.group([older, newer], windowSeconds: 30)
        XCTAssertEqual(result.bundles.first?.latestAt, newer.receivedAt)
    }

    // MARK: - Bundle count accessor

    func test_bundle_count_equalsItemCount() {
        let i1 = item(id: "a", event: .ticketAssigned, receivedAt: base)
        let i2 = item(id: "b", event: .ticketAssigned, receivedAt: base.addingTimeInterval(5))
        let i3 = item(id: "c", event: .ticketAssigned, receivedAt: base.addingTimeInterval(10))
        let result = NotificationGrouper.group([i1, i2, i3])
        XCTAssertEqual(result.bundles.first?.count, 3)
    }

    // MARK: - GroupableNotification defaults

    func test_notificationItem_defaultPriority_derivedFromEvent() {
        let item = GroupableNotification(
            event: .backupFailed,
            title: "T",
            body: "B",
            receivedAt: Date()
        )
        XCTAssertEqual(item.priority, NotificationPriority.defaultPriority(for: .backupFailed))
    }

    func test_notificationItem_category_derivedFromEvent() {
        let item = GroupableNotification(event: .smsInbound, title: "T", body: "B", receivedAt: Date())
        XCTAssertEqual(item.category, .communications)
    }
}
