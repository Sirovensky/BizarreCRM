import Foundation

// MARK: - NotificationDaySection

/// One day's worth of notifications for the grouped list view.
/// Immutable value type; built by `NotificationDaySectionBuilder`.
public struct NotificationDaySection: Identifiable, Sendable {
    /// Stable identifier derived from the header label.
    public let id: String
    /// Human-readable header, e.g. "Today", "Yesterday", "Mon, Apr 21".
    public let header: String
    /// Notifications belonging to this day, preserving server sort order.
    public let items: [NotificationItem]

    public init(id: String, header: String, items: [NotificationItem]) {
        self.id = id
        self.header = header
        self.items = items
    }
}

// MARK: - NotificationDaySectionBuilder

/// Pure function — groups `NotificationItem` values by calendar day.
/// Intentionally free of side effects so it is trivially testable.
public enum NotificationDaySectionBuilder {

    private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoBasic: ISO8601DateFormatter = ISO8601DateFormatter()

    private static let sqlFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let headerFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    /// Parse a date string in either ISO-8601 or SQLite format.
    static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return isoFull.date(from: raw)
            ?? isoBasic.date(from: raw)
            ?? sqlFmt.date(from: raw)
    }

    /// Group `items` into day sections sorted with the most recent day first.
    /// Items whose `createdAt` cannot be parsed are collected under a trailing
    /// "Earlier" section so they aren't silently dropped.
    public static func build(
        from items: [NotificationItem],
        relativeTo reference: Date = Date(),
        calendar: Calendar = .current
    ) -> [NotificationDaySection] {
        var bucketed: [(dayStart: Date, item: NotificationItem)] = []
        var unparseable: [NotificationItem] = []

        for item in items {
            if let date = parseDate(item.createdAt) {
                let start = calendar.startOfDay(for: date)
                bucketed.append((dayStart: start, item: item))
            } else {
                unparseable.append(item)
            }
        }

        // Group by day start
        var dict: [Date: [NotificationItem]] = [:]
        for pair in bucketed {
            dict[pair.dayStart, default: []].append(pair.item)
        }

        // Sort days descending (newest first)
        let sortedDays = dict.keys.sorted(by: >)

        var sections: [NotificationDaySection] = sortedDays.map { day in
            let header = headerLabel(for: day, relativeTo: reference, calendar: calendar)
            return NotificationDaySection(id: header, header: header, items: dict[day]!)
        }

        if !unparseable.isEmpty {
            sections.append(NotificationDaySection(id: "Earlier", header: "Earlier", items: unparseable))
        }

        return sections
    }

    // MARK: - Private helpers

    private static func headerLabel(
        for day: Date,
        relativeTo reference: Date,
        calendar: Calendar
    ) -> String {
        let refStart = calendar.startOfDay(for: reference)
        let diff = calendar.dateComponents([.day], from: day, to: refStart).day ?? 0
        switch diff {
        case 0:  return "Today"
        case 1:  return "Yesterday"
        default: return headerFmt.string(from: day)
        }
    }
}
