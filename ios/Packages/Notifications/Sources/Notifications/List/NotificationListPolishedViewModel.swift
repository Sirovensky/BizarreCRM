import SwiftUI
import Observation
import Core
import Networking
import Sync

// MARK: - NotificationListPolishedViewModel

/// ViewModel for the polished notification list (§13 polish pass).
///
/// Responsibilities:
/// - Load + cache notifications via `NotificationCachedRepository`.
/// - Manage the active filter chip (all / unread / by-type).
/// - Provide grouped sections for the day-header list layout.
/// - Expose mark-read (single) and mark-all-read actions with optimistic UI.
@MainActor
@Observable
public final class NotificationListPolishedViewModel {

    // MARK: - Public state

    public private(set) var allItems: [NotificationItem] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var successBanner: String?
    public private(set) var lastSyncedAt: Date?
    public var activeFilter: NotificationFilterChip = .all
    public var showTypeFilterSheet: Bool = false

    // MARK: - Derived state

    /// Items after applying the active filter, then grouped by calendar day.
    public var daySections: [NotificationDaySection] {
        NotificationDaySectionBuilder.build(from: filteredItems)
    }

    /// Flat filtered list (used for empty-state detection).
    public var filteredItems: [NotificationItem] {
        applyFilter(activeFilter, to: allItems)
    }

    public var unreadCount: Int { allItems.filter { !$0.read }.count }

    public var hasUnread: Bool { unreadCount > 0 }

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let cachedRepo: NotificationCachedRepository?

    // MARK: - Init

    public init(api: APIClient, cachedRepo: NotificationCachedRepository? = nil) {
        self.api = api
        self.cachedRepo = cachedRepo
    }

    // MARK: - Load

    public func load() async {
        if allItems.isEmpty { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do {
            if let repo = cachedRepo {
                allItems = try await repo.listNotifications()
                lastSyncedAt = await repo.lastSyncedAt
            } else {
                allItems = try await api.listNotifications()
            }
        } catch {
            AppLog.ui.error("NotifList load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func forceRefresh() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            if let repo = cachedRepo {
                allItems = try await repo.forceRefresh()
                lastSyncedAt = await repo.lastSyncedAt
            } else {
                allItems = try await api.listNotifications()
            }
        } catch {
            AppLog.ui.error("NotifList forceRefresh failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Actions

    /// Optimistic mark-read for a single row. Reverts on server failure.
    public func markRead(id: Int64) async {
        guard let idx = allItems.firstIndex(where: { $0.id == id }),
              !allItems[idx].read else { return }

        let previous = allItems[idx]
        allItems[idx] = previous.forcedRead()

        do {
            _ = try await api.markNotificationRead(id: id)
        } catch {
            allItems[idx] = previous
            errorMessage = "Couldn't mark as read. Please try again."
        }
    }

    /// Optimistic mark-all-read. Reverts entirely on server failure.
    public func markAllRead() async {
        let previousItems = allItems
        allItems = allItems.map { $0.forcedRead() }
        do {
            let resp = try await api.markAllNotificationsRead()
            let n = resp.updated ?? previousItems.filter { !$0.read }.count
            successBanner = n == 0 ? "Already up to date" : "Marked \(n) as read"
        } catch {
            allItems = previousItems
            errorMessage = "Couldn't mark all as read."
        }
    }

    public func dismissBanner() {
        successBanner = nil
    }

    // MARK: - Filter

    public func setFilter(_ chip: NotificationFilterChip) {
        activeFilter = chip
    }

    // MARK: - Private helpers

    private func applyFilter(
        _ filter: NotificationFilterChip,
        to items: [NotificationItem]
    ) -> [NotificationItem] {
        switch filter {
        case .all:
            return items
        case .unread:
            return items.filter { !$0.read }
        case .byType(let typeFilter):
            return items.filter { typeFilter.matches($0.type) }
        }
    }
}

// MARK: - NotificationItem helpers (immutable copies)

private extension NotificationItem {
    func forcedRead() -> NotificationItem {
        .init(
            id: id, type: type, title: title, message: message,
            entityType: entityType, entityId: entityId,
            isRead: 1, createdAt: createdAt
        )
    }
}
