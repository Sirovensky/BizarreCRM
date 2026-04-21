import Foundation
import Networking

// MARK: - GroupedNotifications

/// Result of grouping: a set of bundles and any singletons that didn't form a group.
public struct GroupedNotifications: Sendable, Equatable {
    public let bundles: [NotificationBundle]
    public let singletons: [GroupableNotification]

    public init(bundles: [NotificationBundle], singletons: [GroupableNotification]) {
        self.bundles = bundles
        self.singletons = singletons
    }
}

// MARK: - NotificationBundle

/// A coalesced group of same-category notifications.
public struct NotificationBundle: Identifiable, Sendable, Equatable {
    public let id: String
    public let category: EventCategory
    public let items: [GroupableNotification]
    public let latestAt: Date

    public var count: Int { items.count }
    public var latestItem: GroupableNotification? { items.first }

    public init(id: String = UUID().uuidString, category: EventCategory, items: [GroupableNotification], latestAt: Date) {
        self.id = id
        self.category = category
        self.items = items
        self.latestAt = latestAt
    }
}

// MARK: - GroupableNotification

/// Lightweight value representing a single in-app notification for grouping purposes.
/// Distinct from `Networking.NotificationItem` (the API model) — this is the
/// client-side enriched model that carries priority and EventCategory.
public struct GroupableNotification: Identifiable, Sendable, Equatable {
    public let id: String
    public let event: NotificationEvent
    public let title: String
    public let body: String
    public let receivedAt: Date
    public let isRead: Bool
    public let priority: NotificationPriority

    public var category: EventCategory { event.category }

    public init(
        id: String = UUID().uuidString,
        event: NotificationEvent,
        title: String,
        body: String,
        receivedAt: Date,
        isRead: Bool = false,
        priority: NotificationPriority? = nil
    ) {
        self.id = id
        self.event = event
        self.title = title
        self.body = body
        self.receivedAt = receivedAt
        self.isRead = isRead
        self.priority = priority ?? NotificationPriority.defaultPriority(for: event)
    }
}

// MARK: - NotificationGrouper

/// Pure function that groups consecutive notifications of the same category
/// arriving within a configurable time window (default 30 s).
///
/// Grouping rules (tested at ≥80% coverage):
/// 1. Items are sorted newest-first before grouping.
/// 2. Consecutive items whose `category` matches AND whose `receivedAt`
///    timestamps are within `windowSeconds` of the *first* item in the run
///    are coalesced into a `NotificationBundle`.
/// 3. A bundle requires at least `minGroupSize` items (default 2).
/// 4. Critical-priority items are never bundled — they always surface individually.
public enum NotificationGrouper {

    // MARK: - Configuration

    public static let defaultWindowSeconds: TimeInterval = 30
    public static let defaultMinGroupSize: Int = 2

    // MARK: - Public API

    /// Group an array of notification items.
    ///
    /// - Parameters:
    ///   - items: Unsorted source items.
    ///   - windowSeconds: Max time span to coalesce (default 30s).
    ///   - minGroupSize: Min items needed to form a bundle (default 2).
    /// - Returns: `GroupedNotifications` with bundles + remaining singletons.
    public static func group(
        _ items: [GroupableNotification],
        windowSeconds: TimeInterval = defaultWindowSeconds,
        minGroupSize: Int = defaultMinGroupSize
    ) -> GroupedNotifications {
        // Sort newest-first so the most recent item anchors each window
        let sorted = items.sorted { $0.receivedAt > $1.receivedAt }

        var bundles: [NotificationBundle] = []
        var singletons: [GroupableNotification] = []
        var processed = Set<String>()

        for item in sorted {
            guard !processed.contains(item.id) else { continue }

            // Critical notifications are never grouped
            if item.priority == .critical {
                processed.insert(item.id)
                singletons.append(item)
                continue
            }

            // Collect candidates: same category, within window, not yet processed, non-critical
            let windowStart = item.receivedAt.addingTimeInterval(-windowSeconds)
            let candidates = sorted.filter { candidate in
                !processed.contains(candidate.id)
                    && candidate.category == item.category
                    && candidate.priority != .critical
                    && candidate.receivedAt >= windowStart
                    && candidate.receivedAt <= item.receivedAt.addingTimeInterval(windowSeconds)
            }

            if candidates.count >= minGroupSize {
                candidates.forEach { processed.insert($0.id) }
                let bundle = NotificationBundle(
                    category: item.category,
                    items: candidates,
                    latestAt: candidates[0].receivedAt
                )
                bundles.append(bundle)
            } else {
                processed.insert(item.id)
                singletons.append(item)
            }
        }

        return GroupedNotifications(bundles: bundles, singletons: singletons)
    }
}
