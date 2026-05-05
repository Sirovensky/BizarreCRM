import XCTest
@testable import Notifications

final class BundleRuleEngineTests: XCTestCase {

    // MARK: - Fixtures

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeNotification(
        id: String = UUID().uuidString,
        event: NotificationEvent = .ticketAssigned,
        title: String = "Notification",
        body: String = "body",
        receivedAt: Date? = nil,
        priority: NotificationPriority? = nil
    ) -> GroupableNotification {
        GroupableNotification(
            id: id,
            event: event,
            title: title,
            body: body,
            receivedAt: receivedAt ?? base,
            priority: priority
        )
    }

    // MARK: - Empty inputs

    func test_applyEmptyRules_allUnmatched() {
        let items = [makeNotification(id: "n1"), makeNotification(id: "n2")]
        let result = BundleRuleEngine.apply(rules: [], to: items)
        XCTAssertTrue(result.groups.isEmpty)
        XCTAssertEqual(result.unmatched.count, 2)
    }

    func test_applyRules_emptyItemList_emptyResult() {
        let rule = BundleRule.ticketsPerCustomer
        let result = BundleRuleEngine.apply(rules: [rule], to: [])
        XCTAssertTrue(result.groups.isEmpty)
        XCTAssertTrue(result.unmatched.isEmpty)
    }

    // MARK: - Category matching

    func test_ruleMatchesCategory_notificationsGrouped() {
        let rule = BundleRule(
            name: "All tickets",
            criteria: BundleRuleCriteria(category: .tickets),
            grouping: .all
        )
        let ticketA = makeNotification(id: "t1", event: .ticketAssigned)
        let ticketB = makeNotification(id: "t2", event: .ticketStatusChangeMine)
        let sms     = makeNotification(id: "s1", event: .smsInbound)

        let result = BundleRuleEngine.apply(rules: [rule], to: [ticketA, ticketB, sms])
        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.groups[0].count, 2)
        XCTAssertEqual(result.unmatched.count, 1)
        XCTAssertEqual(result.unmatched[0].id, "s1")
    }

    // MARK: - Low priority only

    func test_lowPriorityOnly_excludesHighPriority() {
        let rule = BundleRule(
            name: "Low-prio billing",
            criteria: BundleRuleCriteria(category: .billing, lowPriorityOnly: true),
            grouping: .all
        )
        // invoiceOverdue → timeSensitive; invoicePaid → normal; subscriptionRenewal → low
        let urgent = makeNotification(id: "u1", event: .invoiceOverdue)   // timeSensitive
        let normal = makeNotification(id: "n1", event: .invoicePaid)       // normal
        let low    = makeNotification(id: "l1", event: .subscriptionRenewal) // low

        let result = BundleRuleEngine.apply(rules: [rule], to: [urgent, normal, low])
        // normal + low should match (both <= normal)
        let groupedIDs = Set(result.groups.flatMap { $0.items.map(\.id) })
        XCTAssertTrue(groupedIDs.contains("n1"))
        XCTAssertTrue(groupedIDs.contains("l1"))
        XCTAssertFalse(groupedIDs.contains("u1"))
    }

    // MARK: - Critical bypass

    func test_criticalNotifications_neverGrouped() {
        let rule = BundleRule(
            name: "Admin bundle",
            criteria: BundleRuleCriteria(category: .admin),
            grouping: .all
        )
        let crit = makeNotification(id: "c1", event: .backupFailed, priority: .critical)
        let low  = makeNotification(id: "a1", event: .subscriptionRenewal)

        let result = BundleRuleEngine.apply(rules: [rule], to: [crit, low])
        XCTAssertTrue(result.unmatched.contains { $0.id == "c1" })
        XCTAssertTrue(result.groups.flatMap(\.items).contains { $0.id == "a1" })
    }

    // MARK: - First-match wins

    func test_firstMatchWins_secondRuleDoesNotSeeClaimedItems() {
        let rule1 = BundleRule(
            name: "Rule 1 — all tickets",
            criteria: BundleRuleCriteria(category: .tickets),
            grouping: .all
        )
        let rule2 = BundleRule(
            name: "Rule 2 — all tickets again",
            criteria: BundleRuleCriteria(category: .tickets),
            grouping: .byDay
        )
        let t1 = makeNotification(id: "t1", event: .ticketAssigned)
        let t2 = makeNotification(id: "t2", event: .ticketStatusChangeMine)

        let result = BundleRuleEngine.apply(rules: [rule1, rule2], to: [t1, t2])
        // Only rule1's group should appear; rule2 gets nothing
        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.groups[0].ruleName, "Rule 1 — all tickets")
        XCTAssertTrue(result.unmatched.isEmpty)
    }

    // MARK: - Disabled rules skipped

    func test_disabledRule_isSkipped() {
        let rule = BundleRule(
            name: "Disabled rule",
            criteria: BundleRuleCriteria(category: .tickets),
            grouping: .all,
            isEnabled: false
        )
        let t1 = makeNotification(id: "t1", event: .ticketAssigned)
        let result = BundleRuleEngine.apply(rules: [rule], to: [t1])
        XCTAssertTrue(result.groups.isEmpty)
        XCTAssertEqual(result.unmatched.count, 1)
    }

    // MARK: - Grouping: .all

    func test_groupingAll_allMatchedInOneGroup() {
        let rule = BundleRule(
            name: "All SMS",
            criteria: BundleRuleCriteria(category: .communications),
            grouping: .all
        )
        let items = (0..<4).map { makeNotification(id: "s\($0)", event: .smsInbound) }
        let result = BundleRuleEngine.apply(rules: [rule], to: items)
        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.groups[0].count, 4)
    }

    func test_groupingAll_groupKey_containsRuleID() {
        let rule = BundleRule(
            id: "test-rule-id",
            name: "All SMS",
            criteria: BundleRuleCriteria(category: .communications),
            grouping: .all
        )
        let items = [makeNotification(event: .smsInbound), makeNotification(event: .smsInbound)]
        let result = BundleRuleEngine.apply(rules: [rule], to: items)
        XCTAssertTrue(result.groups[0].groupKey.contains("test-rule-id"))
        XCTAssertTrue(result.groups[0].groupKey.hasSuffix(":all"))
    }

    // MARK: - Grouping: .byDay

    func test_groupingByDay_separatesAcrossDays() {
        let rule = BundleRule(
            name: "Invoices by day",
            criteria: BundleRuleCriteria(category: .billing),
            grouping: .byDay
        )

        // Two items on "today", one item on "yesterday"
        let today     = base
        let yesterday = base.addingTimeInterval(-86_400)

        let i1 = makeNotification(id: "i1", event: .invoicePaid, receivedAt: today)
        let i2 = makeNotification(id: "i2", event: .invoicePaid, receivedAt: today.addingTimeInterval(3_600))
        let i3 = makeNotification(id: "i3", event: .invoicePaid, receivedAt: yesterday)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let result = BundleRuleEngine.apply(rules: [rule], to: [i1, i2, i3], calendar: calendar)
        XCTAssertEqual(result.groups.count, 2, "Should produce two groups: one per day")
        let groupSizes = result.groups.map(\.count).sorted()
        XCTAssertEqual(groupSizes, [1, 2])
    }

    // MARK: - Grouping: .byEntity

    func test_groupingByEntity_groupsPerEntityID() {
        let rule = BundleRule(
            name: "Tickets per customer",
            criteria: BundleRuleCriteria(category: .tickets),
            grouping: .byEntity
        )

        // Use EntityID: prefix convention supported by BundleRuleEngine
        let t1 = makeNotification(id: "t1", event: .ticketAssigned, body: "EntityID:cust-A\nnotes")
        let t2 = makeNotification(id: "t2", event: .ticketAssigned, body: "EntityID:cust-A\nnotes")
        let t3 = makeNotification(id: "t3", event: .ticketAssigned, body: "EntityID:cust-B\nnotes")

        let result = BundleRuleEngine.apply(rules: [rule], to: [t1, t2, t3])
        XCTAssertEqual(result.groups.count, 2, "Should produce one group per customer entity")
        let custA = result.groups.first { $0.groupKey.contains("cust-A") }
        let custB = result.groups.first { $0.groupKey.contains("cust-B") }
        XCTAssertEqual(custA?.count, 2)
        XCTAssertEqual(custB?.count, 1)
    }

    func test_groupingByEntity_noEntityID_fallsBackToCategory() {
        let rule = BundleRule(
            name: "Tickets",
            criteria: BundleRuleCriteria(category: .tickets),
            grouping: .byEntity
        )
        // No EntityID prefix → fallback to category name
        let t1 = makeNotification(id: "t1", event: .ticketAssigned, body: "plain body")
        let t2 = makeNotification(id: "t2", event: .ticketAssigned, body: "plain body")

        let result = BundleRuleEngine.apply(rules: [rule], to: [t1, t2])
        // Both should land in the same group (same fallback key)
        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.groups[0].count, 2)
    }

    // MARK: - No-duplicate guarantee

    func test_eachNotificationClaimedOnce() {
        let rule1 = BundleRule(name: "Tickets", criteria: BundleRuleCriteria(category: .tickets), grouping: .all)
        let rule2 = BundleRule(name: "All-tickets-again", criteria: BundleRuleCriteria(category: .tickets), grouping: .all)

        let items = (0..<5).map { makeNotification(id: "t\($0)", event: .ticketAssigned) }
        let result = BundleRuleEngine.apply(rules: [rule1, rule2], to: items)

        let totalGrouped  = result.groups.reduce(0) { $0 + $1.count }
        let totalUnmatched = result.unmatched.count
        XCTAssertEqual(totalGrouped + totalUnmatched, items.count, "Each item should appear exactly once")
    }

    // MARK: - Preset rules

    func test_presetTicketsPerCustomer_isEnabled() {
        XCTAssertTrue(BundleRule.ticketsPerCustomer.isEnabled)
        XCTAssertEqual(BundleRule.ticketsPerCustomer.criteria.category, .tickets)
        XCTAssertEqual(BundleRule.ticketsPerCustomer.grouping, .byEntity)
    }

    func test_presetInvoicesPerDay_isEnabled() {
        XCTAssertTrue(BundleRule.invoicesPerDay.isEnabled)
        XCTAssertEqual(BundleRule.invoicesPerDay.criteria.category, .billing)
        XCTAssertEqual(BundleRule.invoicesPerDay.grouping, .byDay)
    }

    // MARK: - BundleRule copy-on-write

    func test_bundleRule_withName_doesNotMutateOriginal() {
        let original = BundleRule.ticketsPerCustomer
        let updated  = original.withName("New name")
        XCTAssertNotEqual(updated.name, original.name)
        XCTAssertEqual(original.name, "Tickets per customer")
    }

    func test_bundleRule_withEnabled_false() {
        let disabled = BundleRule.ticketsPerCustomer.withEnabled(false)
        XCTAssertFalse(disabled.isEnabled)
    }

    func test_bundleRule_withGrouping_updatesGrouping() {
        let rule = BundleRule.ticketsPerCustomer.withGrouping(.all)
        XCTAssertEqual(rule.grouping, .all)
    }

    func test_bundleRule_withCriteria_updatesCriteria() {
        let newCriteria = BundleRuleCriteria(category: .communications, lowPriorityOnly: true)
        let rule = BundleRule.ticketsPerCustomer.withCriteria(newCriteria)
        XCTAssertEqual(rule.criteria.category, .communications)
        XCTAssertTrue(rule.criteria.lowPriorityOnly)
    }

    // MARK: - BundleRuleCriteria matching

    func test_criteria_noCategoryFilter_matchesAllCategories() {
        let criteria = BundleRuleCriteria()
        let n = makeNotification(event: .invoicePaid)
        XCTAssertTrue(criteria.matches(n))
    }

    func test_criteria_categoryFilter_rejectsDifferentCategory() {
        let criteria = BundleRuleCriteria(category: .tickets)
        let n = makeNotification(event: .invoicePaid) // billing category
        XCTAssertFalse(criteria.matches(n))
    }

    func test_criteria_eventsFilter_matchesSpecificEvent() {
        let criteria = BundleRuleCriteria(events: [.invoicePaid])
        let match    = makeNotification(event: .invoicePaid)
        let noMatch  = makeNotification(event: .invoiceOverdue)
        XCTAssertTrue(criteria.matches(match))
        XCTAssertFalse(criteria.matches(noMatch))
    }

    func test_criteria_lowPriorityOnly_rejectsCritical() {
        let criteria = BundleRuleCriteria(lowPriorityOnly: true)
        let crit = makeNotification(event: .backupFailed, priority: .critical)
        XCTAssertFalse(criteria.matches(crit))
    }

    func test_criteria_lowPriorityOnly_rejectsTimeSensitive() {
        let criteria = BundleRuleCriteria(lowPriorityOnly: true)
        let ts = makeNotification(event: .ticketAssigned, priority: .timeSensitive)
        XCTAssertFalse(criteria.matches(ts))
    }

    func test_criteria_lowPriorityOnly_acceptsNormal() {
        let criteria = BundleRuleCriteria(lowPriorityOnly: true)
        let n = makeNotification(event: .invoicePaid, priority: .normal)
        XCTAssertTrue(criteria.matches(n))
    }

    // MARK: - Codable

    func test_bundleRule_codable_roundTrip() throws {
        let rule    = BundleRule.ticketsPerCustomer
        let data    = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(BundleRule.self, from: data)
        XCTAssertEqual(decoded.id, rule.id)
        XCTAssertEqual(decoded.name, rule.name)
        XCTAssertEqual(decoded.grouping, rule.grouping)
    }

    func test_bundleRuleCriteria_codable_roundTrip() throws {
        let criteria = BundleRuleCriteria(category: .billing, lowPriorityOnly: true)
        let data     = try JSONEncoder().encode(criteria)
        let decoded  = try JSONDecoder().decode(BundleRuleCriteria.self, from: data)
        XCTAssertEqual(decoded.category, criteria.category)
        XCTAssertEqual(decoded.lowPriorityOnly, true)
    }

    // MARK: - RuleBundle

    func test_ruleBundle_count_equalsItemsCount() {
        let items = [makeNotification(), makeNotification()]
        let bundle = RuleBundle(ruleName: "Test", groupKey: "k", items: items)
        XCTAssertEqual(bundle.count, 2)
    }

    // MARK: - Multirule pipeline

    func test_multipleRules_eachClaimsItsOwn() {
        let ticketRule = BundleRule(name: "Tickets", criteria: BundleRuleCriteria(category: .tickets), grouping: .all)
        let smsRule    = BundleRule(name: "SMS",     criteria: BundleRuleCriteria(category: .communications), grouping: .all)

        let ticket = makeNotification(id: "t1", event: .ticketAssigned)
        let sms    = makeNotification(id: "s1", event: .smsInbound)
        let inv    = makeNotification(id: "i1", event: .invoicePaid)  // billing → unmatched

        let result = BundleRuleEngine.apply(rules: [ticketRule, smsRule], to: [ticket, sms, inv])
        XCTAssertEqual(result.groups.count, 2)
        XCTAssertEqual(result.unmatched.count, 1)
        XCTAssertEqual(result.unmatched[0].id, "i1")
    }
}
