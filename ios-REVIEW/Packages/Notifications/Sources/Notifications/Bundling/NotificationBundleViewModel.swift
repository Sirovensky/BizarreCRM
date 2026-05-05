import Foundation
import Observation

// MARK: - NotificationBundleViewModel

/// `@Observable` VM that aggregates incoming notifications in real time,
/// coalescing same-category items arriving within a 30-second window.
@MainActor
@Observable
public final class NotificationBundleViewModel {

    // MARK: - Public state

    public private(set) var groupedResult: GroupedNotifications = GroupedNotifications(
        bundles: [],
        singletons: []
    )

    // MARK: - Private

    private var rawItems: [GroupableNotification] = []
    private let windowSeconds: TimeInterval
    private let minGroupSize: Int

    // MARK: - Init

    public init(
        windowSeconds: TimeInterval = NotificationGrouper.defaultWindowSeconds,
        minGroupSize: Int = NotificationGrouper.defaultMinGroupSize
    ) {
        self.windowSeconds = windowSeconds
        self.minGroupSize = minGroupSize
    }

    // MARK: - Public API

    /// Ingest a new notification item. Triggers re-grouping synchronously.
    public func receive(_ item: GroupableNotification) {
        rawItems.append(item)
        regroup()
    }

    /// Replace the entire item set (e.g. after pull-to-refresh).
    public func replace(with items: [GroupableNotification]) {
        rawItems = items
        regroup()
    }

    /// Dismiss an item from the in-memory list.
    public func dismiss(id: String) {
        rawItems.removeAll { $0.id == id }
        regroup()
    }

    // MARK: - Private

    private func regroup() {
        groupedResult = NotificationGrouper.group(
            rawItems,
            windowSeconds: windowSeconds,
            minGroupSize: minGroupSize
        )
    }
}
