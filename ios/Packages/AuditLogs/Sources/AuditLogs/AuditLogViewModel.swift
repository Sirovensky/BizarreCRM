import Foundation
import Observation
import Core

// MARK: - Filter state

/// All filter criteria for the audit log list.
public struct AuditLogFilters: Sendable, Equatable {
    public var actorId: String?
    public var actions: [String]    // multi-select
    public var entityType: String?
    public var since: Date?
    public var until: Date?
    public var query: String

    public static let empty = AuditLogFilters(
        actorId: nil, actions: [], entityType: nil,
        since: nil, until: nil, query: ""
    )

    public init(
        actorId: String? = nil,
        actions: [String] = [],
        entityType: String? = nil,
        since: Date? = nil,
        until: Date? = nil,
        query: String = ""
    ) {
        self.actorId = actorId
        self.actions = actions
        self.entityType = entityType
        self.since = since
        self.until = until
        self.query = query
    }

    public var isActive: Bool {
        actorId != nil || !actions.isEmpty || entityType != nil ||
        since != nil || until != nil || !query.isEmpty
    }
}

/// Quick-range presets for the filter chip bar.
public enum AuditDateRange: String, CaseIterable, Sendable {
    case last24h  = "Last 24h"
    case thisWeek = "This week"
    case thisMonth = "This month"
    case custom   = "Custom"

    public func dateInterval(now: Date = Date()) -> (since: Date, until: Date)? {
        let cal = Calendar.current
        switch self {
        case .last24h:
            return (since: now.addingTimeInterval(-86_400), until: now)
        case .thisWeek:
            guard let start = cal.dateInterval(of: .weekOfYear, for: now)?.start else { return nil }
            return (since: start, until: now)
        case .thisMonth:
            guard let start = cal.dateInterval(of: .month, for: now)?.start else { return nil }
            return (since: start, until: now)
        case .custom:
            return nil
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class AuditLogViewModel {

    // MARK: State

    public private(set) var entries: [AuditLogEntry] = []
    public private(set) var isLoading = false
    public private(set) var isLoadingMore = false
    public private(set) var errorMessage: String?
    public private(set) var nextCursor: String?
    public private(set) var hasMore = false
    public private(set) var hasAccess = true

    public var filters: AuditLogFilters = .empty
    public var selectedRange: AuditDateRange? = nil
    public var showFilterSheet = false

    // MARK: Dependencies

    @ObservationIgnored private let repository: AuditLogRepository
    @ObservationIgnored private let accessPolicy: () -> Bool
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    public init(
        repository: AuditLogRepository,
        accessPolicy: @escaping @Sendable () -> Bool = { AuditLogAccessPolicy.canViewAuditLogs() }
    ) {
        self.repository = repository
        self.accessPolicy = accessPolicy
    }

    // MARK: Public interface

    /// Initial or refresh load — resets pagination.
    public func load() async {
        guard checkAccess() else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await repository.fetch(filters: filters, cursor: nil)
            entries = page.entries
            nextCursor = page.nextCursor
            hasMore = page.nextCursor != nil
        } catch {
            AppLog.ui.error("AuditLogs load error: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    /// Cursor pagination — appends next page.
    public func loadMore() async {
        guard hasMore, let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await repository.fetch(filters: filters, cursor: cursor)
            entries += page.entries
            nextCursor = page.nextCursor
            hasMore = page.nextCursor != nil
        } catch {
            AppLog.ui.error("AuditLogs loadMore error: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Call from the list to trigger next-page fetch when a row is nearing the end.
    public func loadMoreIfNeeded(entryId: String) {
        guard let idx = entries.firstIndex(where: { $0.id == entryId }) else { return }
        let threshold = max(0, entries.count - 5)
        if idx >= threshold {
            Task { await loadMore() }
        }
    }

    /// Applies a quick-range preset. Passing `nil` clears date filters.
    public func applyDateRange(_ range: AuditDateRange?) {
        selectedRange = range
        if let range, let interval = range.dateInterval() {
            filters = AuditLogFilters(
                actorId:    filters.actorId,
                actions:    filters.actions,
                entityType: filters.entityType,
                since:      interval.since,
                until:      interval.until,
                query:      filters.query
            )
        } else if range == .custom {
            // Keep any manually set since/until; clear preset-derived ones only
            // if both are still nil — caller sets them via the DatePicker.
        } else {
            filters = AuditLogFilters(
                actorId:    filters.actorId,
                actions:    filters.actions,
                entityType: filters.entityType,
                since:      nil,
                until:      nil,
                query:      filters.query
            )
        }
        Task { await load() }
    }

    /// Debounced query search.
    public func onQueryChange(_ q: String) {
        filters = AuditLogFilters(
            actorId:    filters.actorId,
            actions:    filters.actions,
            entityType: filters.entityType,
            since:      filters.since,
            until:      filters.until,
            query:      q
        )
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    /// Apply filter sheet changes and reload.
    public func applyFilters(_ updated: AuditLogFilters) {
        filters = updated
        selectedRange = nil
        Task { await load() }
    }

    /// Clear all filters.
    public func clearFilters() {
        filters = .empty
        selectedRange = nil
        Task { await load() }
    }

    // MARK: Private

    @discardableResult
    private func checkAccess() -> Bool {
        let allowed = accessPolicy()
        hasAccess = allowed
        return allowed
    }
}
