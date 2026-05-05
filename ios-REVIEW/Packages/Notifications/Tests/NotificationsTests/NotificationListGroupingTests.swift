import XCTest
@testable import Notifications

final class NotificationListGroupingTests: XCTestCase {

    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func item(
        id: String = UUID().uuidString,
        event: NotificationEvent,
        receivedAt: Date
    ) -> GroupableNotification {
        GroupableNotification(id: id, event: event, title: "T", body: "B", receivedAt: receivedAt)
    }

    private let today = Date()
    private var yesterday: Date { Date().addingTimeInterval(-86_400) }
    private var lastWeek: Date { Date().addingTimeInterval(-5 * 86_400) }

    // MARK: - allCases

    func test_allCases_count3() {
        XCTAssertEqual(NotificationListGrouping.allCases.count, 3)
    }

    // MARK: - byTime grouping

    func test_byTime_todayItems_inTodaySection() {
        let items = [item(event: .ticketAssigned, receivedAt: today)]
        let sections = NotificationListGrouping.byTime.apply(to: items, calendar: utcCalendar)
        XCTAssertEqual(sections.first?.header, "Today")
    }

    func test_byTime_yesterdayItems_inYesterdaySection() {
        let items = [item(event: .ticketAssigned, receivedAt: yesterday)]
        let sections = NotificationListGrouping.byTime.apply(to: items, calendar: utcCalendar)
        XCTAssertEqual(sections.first?.header, "Yesterday")
    }

    func test_byTime_mixedDates_multiSections() {
        let items = [
            item(event: .ticketAssigned, receivedAt: today),
            item(event: .ticketAssigned, receivedAt: yesterday)
        ]
        let sections = NotificationListGrouping.byTime.apply(to: items, calendar: utcCalendar)
        XCTAssertEqual(sections.count, 2)
    }

    func test_byTime_sameDayItems_groupedTogether() {
        let now = today
        let items = [
            item(event: .ticketAssigned, receivedAt: now),
            item(event: .smsInbound, receivedAt: now.addingTimeInterval(-30))
        ]
        let sections = NotificationListGrouping.byTime.apply(to: items, calendar: utcCalendar)
        XCTAssertEqual(sections.first?.items.count, 2)
    }

    // MARK: - byCategory grouping

    func test_byCategory_groupsByCategoryHeader() {
        let items = [
            item(event: .ticketAssigned, receivedAt: today),
            item(event: .smsInbound, receivedAt: today)
        ]
        let sections = NotificationListGrouping.byCategory.apply(to: items)
        let headers = sections.map(\.header)
        XCTAssertTrue(headers.contains("Tickets"))
        XCTAssertTrue(headers.contains("Communications"))
    }

    func test_byCategory_emptyCategoriesOmitted() {
        let items = [item(event: .ticketAssigned, receivedAt: today)]
        let sections = NotificationListGrouping.byCategory.apply(to: items)
        // Only Tickets section, no others
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.header, "Tickets")
    }

    func test_byCategory_sameCategory_singleSection() {
        let items = [
            item(event: .ticketAssigned, receivedAt: today),
            item(event: .ticketStatusChangeMine, receivedAt: today)
        ]
        let sections = NotificationListGrouping.byCategory.apply(to: items)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.items.count, 2)
    }

    // MARK: - bySource grouping

    func test_bySource_groupsByEventPrefix() {
        let items = [
            item(event: .ticketAssigned, receivedAt: today),
            item(event: .ticketStatusChangeMine, receivedAt: today),
            item(event: .smsInbound, receivedAt: today)
        ]
        let sections = NotificationListGrouping.bySource.apply(to: items)
        let headers = sections.map(\.header)
        XCTAssertTrue(headers.contains("ticket"))
        XCTAssertTrue(headers.contains("sms"))
    }

    // MARK: - Empty input

    func test_byTime_emptyInput_emptySections() {
        let sections = NotificationListGrouping.byTime.apply(to: [], calendar: utcCalendar)
        XCTAssertTrue(sections.isEmpty)
    }

    func test_byCategory_emptyInput_emptySections() {
        let sections = NotificationListGrouping.byCategory.apply(to: [])
        XCTAssertTrue(sections.isEmpty)
    }

    func test_bySource_emptyInput_emptySections() {
        let sections = NotificationListGrouping.bySource.apply(to: [])
        XCTAssertTrue(sections.isEmpty)
    }

    // MARK: - No item lost

    func test_byTime_noItemLost() {
        let items = (0..<5).map { _ in item(event: .ticketAssigned, receivedAt: self.today) }
        let sections = NotificationListGrouping.byTime.apply(to: items, calendar: utcCalendar)
        let total = sections.reduce(0) { $0 + $1.items.count }
        XCTAssertEqual(total, items.count)
    }

    func test_byCategory_noItemLost() {
        let items = [
            item(event: .ticketAssigned, receivedAt: today),
            item(event: .smsInbound, receivedAt: today),
            item(event: .invoicePaid, receivedAt: today)
        ]
        let sections = NotificationListGrouping.byCategory.apply(to: items)
        let total = sections.reduce(0) { $0 + $1.items.count }
        XCTAssertEqual(total, items.count)
    }

    // MARK: - Accessibility labels

    func test_allGroupings_haveAccessibilityLabels() {
        for grouping in NotificationListGrouping.allCases {
            XCTAssertFalse(grouping.accessibilityLabel.isEmpty)
        }
    }

    func test_allGroupings_haveIconNames() {
        for grouping in NotificationListGrouping.allCases {
            XCTAssertFalse(grouping.iconName.isEmpty)
        }
    }
}
