import XCTest
@testable import Notifications

final class FocusFilterDescriptorTests: XCTestCase {

    private func makeItem(
        event: NotificationEvent = .ticketAssigned,
        priority: NotificationPriority? = nil
    ) -> GroupableNotification {
        GroupableNotification(
            event: event,
            title: "Test",
            body: "Body",
            receivedAt: Date(),
            priority: priority
        )
    }

    // MARK: - Default descriptor

    func test_defaultDescriptor_hasPoliciesForWorkDndSleep() {
        let desc = FocusFilterDescriptor.defaultDescriptor()
        XCTAssertNotNil(desc.policies[.work])
        XCTAssertNotNil(desc.policies[.doNotDisturb])
        XCTAssertNotNil(desc.policies[.sleep])
    }

    // MARK: - shouldShow: no active mode → always show

    func test_shouldShow_noActiveMode_returnsTrue() {
        let desc = FocusFilterDescriptor.defaultDescriptor()
        let item = makeItem()
        XCTAssertTrue(desc.shouldShow(item: item, activeMode: nil))
    }

    // MARK: - shouldShow: DND → only critical override

    func test_shouldShow_dndMode_nonCritical_suppressedByDefault() {
        let desc = FocusFilterDescriptor.defaultDescriptor()
        let item = makeItem(event: .lowStock, priority: .normal)
        // DND default allows no categories
        XCTAssertFalse(desc.shouldShow(item: item, activeMode: .doNotDisturb))
    }

    func test_shouldShow_dndMode_criticalOverride_showsCritical() {
        let desc = FocusFilterDescriptor.defaultDescriptor()
        let item = makeItem(event: .backupFailed, priority: .critical)
        XCTAssertTrue(desc.shouldShow(item: item, activeMode: .doNotDisturb))
    }

    // MARK: - shouldShow: Work mode → allows tickets + comms + admin

    func test_shouldShow_workMode_ticketItem_shows() {
        let desc = FocusFilterDescriptor.defaultDescriptor()
        let item = makeItem(event: .ticketAssigned, priority: .timeSensitive)
        XCTAssertTrue(desc.shouldShow(item: item, activeMode: .work))
    }

    func test_shouldShow_workMode_billingItem_suppressed() {
        let desc = FocusFilterDescriptor.defaultDescriptor()
        let item = makeItem(event: .invoicePaid, priority: .normal)
        XCTAssertFalse(desc.shouldShow(item: item, activeMode: .work))
    }

    // MARK: - shouldShow: Sleep → suppress all including critical

    func test_shouldShow_sleepMode_criticalNotOverridden() {
        let desc = FocusFilterDescriptor.defaultDescriptor()
        let item = makeItem(event: .backupFailed, priority: .critical)
        // Sleep default has allowCriticalOverride = false
        XCTAssertFalse(desc.shouldShow(item: item, activeMode: .sleep))
    }

    // MARK: - shouldShow: no policy for mode → allow

    func test_shouldShow_modeWithNoPolicy_returnsTrue() {
        let desc = FocusFilterDescriptor(policies: [:])
        let item = makeItem()
        XCTAssertTrue(desc.shouldShow(item: item, activeMode: .personal))
    }

    // MARK: - updatingPolicy: immutable update

    func test_updatingPolicy_createsNewDescriptor() {
        let desc = FocusFilterDescriptor.defaultDescriptor()
        let newPolicy = FocusFilterPolicy(
            focusMode: .custom,
            allowedCategories: [.billing],
            allowCriticalOverride: true
        )
        let updated = desc.updatingPolicy(newPolicy)
        XCTAssertNotNil(updated.policies[.custom])
        // Original unchanged
        XCTAssertNil(desc.policies[.custom])
    }

    func test_updatingPolicy_replacesExistingPolicy() {
        let desc = FocusFilterDescriptor.defaultDescriptor()
        let newWorkPolicy = FocusFilterPolicy(
            focusMode: .work,
            allowedCategories: [.billing],
            allowCriticalOverride: false
        )
        let updated = desc.updatingPolicy(newWorkPolicy)
        XCTAssertEqual(updated.policies[.work]?.allowedCategories, [.billing])
        XCTAssertEqual(updated.policies[.work]?.allowCriticalOverride, false)
    }

    // MARK: - FocusFilterPolicy: presets

    func test_workDefault_allowedCategoriesContainsTickets() {
        let p = FocusFilterPolicy.workDefault()
        XCTAssertTrue(p.allowedCategories.contains(.tickets))
    }

    func test_dndDefault_allowedCategoriesIsEmpty() {
        let p = FocusFilterPolicy.doNotDisturbDefault()
        XCTAssertTrue(p.allowedCategories.isEmpty)
    }

    func test_sleepDefault_allowCriticalOverrideIsFalse() {
        let p = FocusFilterPolicy.sleepDefault()
        XCTAssertFalse(p.allowCriticalOverride)
    }

    // MARK: - FocusMode

    func test_focusMode_allCases_haveIconNames() {
        for mode in FocusMode.allCases {
            XCTAssertFalse(mode.iconName.isEmpty)
        }
    }
}
