import Foundation

// MARK: - NotificationListGrouping

/// Grouping strategy for the notification list view.
/// User toggles via sort menu on the notification list.
public enum NotificationListGrouping: String, Sendable, CaseIterable, Identifiable {
    case byTime     = "By Time"
    case byCategory = "By Category"
    case bySource   = "By Source"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .byTime:     return "clock"
        case .byCategory: return "tag"
        case .bySource:   return "person.crop.circle"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .byTime:     return "Group notifications by time"
        case .byCategory: return "Group notifications by category"
        case .bySource:   return "Group notifications by source entity"
        }
    }

    // MARK: - Apply grouping

    /// Group a flat list of items according to the selected strategy.
    /// Returns sections of `(header: String, items: [GroupableNotification])`.
    public func apply(to items: [GroupableNotification], calendar: Calendar = .current) -> [(header: String, items: [GroupableNotification])] {
        switch self {
        case .byTime:
            return groupByTime(items, calendar: calendar)
        case .byCategory:
            return groupByCategory(items)
        case .bySource:
            return groupBySource(items)
        }
    }

    // MARK: - Time grouping

    private func groupByTime(_ items: [GroupableNotification], calendar: Calendar) -> [(header: String, items: [GroupableNotification])] {
        let sorted = items.sorted { $0.receivedAt > $1.receivedAt }
        var result: [(header: String, items: [GroupableNotification])] = []
        var seen: [String: Int] = [:]

        for item in sorted {
            let key = timeGroupKey(for: item.receivedAt, calendar: calendar)
            if let idx = seen[key] {
                result[idx].items.append(item)
            } else {
                seen[key] = result.count
                result.append((header: key, items: [item]))
            }
        }
        return result
    }

    private func timeGroupKey(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date)    { return "Today" }
        if calendar.isDateInYesterday(date){ return "Yesterday" }
        let comps = calendar.dateComponents([.day], from: date, to: Date())
        if let days = comps.day {
            if days < 7  { return "This Week" }
            if days < 30 { return "This Month" }
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: date)
    }

    // MARK: - Category grouping

    private func groupByCategory(_ items: [GroupableNotification]) -> [(header: String, items: [GroupableNotification])] {
        let sorted = items.sorted { $0.receivedAt > $1.receivedAt }
        var dict: [EventCategory: [GroupableNotification]] = [:]
        for item in sorted {
            dict[item.category, default: []].append(item)
        }
        return EventCategory.allCases
            .compactMap { cat -> (header: String, items: [GroupableNotification])? in
                guard let catItems = dict[cat], !catItems.isEmpty else { return nil }
                return (header: cat.rawValue, items: catItems)
            }
    }

    // MARK: - Source grouping

    /// Groups by `NotificationEvent` raw value prefix (the entity/source).
    private func groupBySource(_ items: [GroupableNotification]) -> [(header: String, items: [GroupableNotification])] {
        let sorted = items.sorted { $0.receivedAt > $1.receivedAt }
        var dict: [String: [GroupableNotification]] = [:]
        for item in sorted {
            let source = sourceKey(for: item.event)
            dict[source, default: []].append(item)
        }
        return dict.keys.sorted().compactMap { key -> (header: String, items: [GroupableNotification])? in
            guard let srcItems = dict[key], !srcItems.isEmpty else { return nil }
            return (header: key, items: srcItems)
        }
    }

    private func sourceKey(for event: NotificationEvent) -> String {
        // e.g. "ticket.assigned" → "ticket", "sms.inbound" → "sms"
        let parts = event.rawValue.split(separator: ".")
        return parts.first.map(String.init) ?? event.rawValue
    }
}
