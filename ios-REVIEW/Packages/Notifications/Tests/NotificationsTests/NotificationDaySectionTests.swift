import Testing
import Foundation
@testable import Notifications

@Suite("NotificationDaySectionBuilder")
struct NotificationDaySectionBuilderTests {

    // MARK: - Helpers

    static func item(id: Int64, type: String = "ticket", daysAgo: Int) -> NotificationItem {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return NotificationItem(
            id: id, type: type, title: "T\(id)", message: nil,
            entityType: nil, entityId: nil, isRead: 0,
            createdAt: fmt.string(from: date)
        )
    }

    // MARK: - Grouping

    @Test("Items from today group into Today section")
    func todaySection() {
        let items = [Self.item(id: 1, daysAgo: 0), Self.item(id: 2, daysAgo: 0)]
        let sections = NotificationDaySectionBuilder.build(from: items)
        #expect(sections.first?.header == "Today")
        #expect(sections.first?.items.count == 2)
    }

    @Test("Items from yesterday group into Yesterday section")
    func yesterdaySection() {
        let items = [Self.item(id: 3, daysAgo: 1)]
        let sections = NotificationDaySectionBuilder.build(from: items)
        #expect(sections.first?.header == "Yesterday")
    }

    @Test("Items from 3 days ago use formatted date header")
    func olderSection() {
        let items = [Self.item(id: 4, daysAgo: 3)]
        let sections = NotificationDaySectionBuilder.build(from: items)
        let header = sections.first?.header ?? ""
        // Should be something like "Thu, Apr 20" — just check it's not Today/Yesterday
        #expect(header != "Today")
        #expect(header != "Yesterday")
        #expect(!header.isEmpty)
    }

    @Test("Items across three days produce three sections")
    func threeDaySections() {
        let items = [
            Self.item(id: 1, daysAgo: 0),
            Self.item(id: 2, daysAgo: 1),
            Self.item(id: 3, daysAgo: 5),
        ]
        let sections = NotificationDaySectionBuilder.build(from: items)
        #expect(sections.count == 3)
    }

    @Test("Empty input produces empty sections")
    func emptyInput() {
        let sections = NotificationDaySectionBuilder.build(from: [])
        #expect(sections.isEmpty)
    }

    @Test("Sections are sorted newest-first")
    func sectionsDescending() {
        let items = [
            Self.item(id: 1, daysAgo: 5),
            Self.item(id: 2, daysAgo: 0),
            Self.item(id: 3, daysAgo: 2),
        ]
        let sections = NotificationDaySectionBuilder.build(from: items)
        #expect(sections.first?.header == "Today")
    }

    @Test("Items with unparseable dates go to Earlier section")
    func unparseableDate() {
        let bad = NotificationItem(
            id: 99, type: "system", title: "Oops", message: nil,
            entityType: nil, entityId: nil, isRead: 0,
            createdAt: "not-a-date"
        )
        let sections = NotificationDaySectionBuilder.build(from: [bad])
        #expect(sections.first?.header == "Earlier")
        #expect(sections.first?.items.count == 1)
    }

    @Test("Items with nil createdAt go to Earlier section")
    func nilDate() {
        let bad = NotificationItem(
            id: 100, type: "system", title: "None", message: nil,
            entityType: nil, entityId: nil, isRead: 0,
            createdAt: nil
        )
        let sections = NotificationDaySectionBuilder.build(from: [bad])
        #expect(sections.first?.header == "Earlier")
    }

    @Test("Two items same day are in one section")
    func sameDay() {
        let items = (0..<5).map { i in Self.item(id: Int64(i), daysAgo: 0) }
        let sections = NotificationDaySectionBuilder.build(from: items)
        #expect(sections.count == 1)
        #expect(sections.first?.items.count == 5)
    }

    // MARK: - ISO 8601 parsing

    @Test("ISO-8601 full format parses correctly")
    func isoFullFormat() {
        let iso = NotificationDaySectionBuilder.parseDate("2026-04-20T12:00:00.000Z")
        #expect(iso != nil)
    }

    @Test("ISO-8601 basic format parses correctly")
    func isoBasicFormat() {
        let iso = NotificationDaySectionBuilder.parseDate("2026-04-20T12:00:00Z")
        #expect(iso != nil)
    }

    @Test("SQLite format parses correctly")
    func sqliteFormat() {
        let sql = NotificationDaySectionBuilder.parseDate("2026-04-20 12:00:00")
        #expect(sql != nil)
    }
}
