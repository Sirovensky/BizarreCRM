import Foundation
import Observation
import Core
import Networking

// MARK: - Filter model

/// Active filters for the customer list (§5.1).
public struct CustomerListFilter: Equatable, Sendable {
    public var ltvTier: String?        // "vip" | "regular" | "at_risk"
    public var healthBand: String?     // "good" | "fair" | "poor"
    public var balanceGtZero: Bool = false
    public var hasOpenTickets: Bool = false
    public var city: String?
    public var state: String?
    public var tag: String?

    public var isActive: Bool {
        ltvTier != nil || healthBand != nil || balanceGtZero ||
        hasOpenTickets || city != nil || state != nil || tag != nil
    }

    /// Number of independently active filter criteria — used to badge the filter toolbar button.
    public var activeCount: Int {
        [
            ltvTier != nil,
            healthBand != nil,
            balanceGtZero,
            hasOpenTickets,
            city != nil,
            state != nil,
            tag != nil
        ].filter { $0 }.count
    }

    public init() {}
}

// MARK: - CustomerListViewModel

@MainActor
@Observable
public final class CustomerListViewModel {
    public private(set) var customers: [CustomerSummary] = []
    public private(set) var isLoading: Bool = false
    public private(set) var isRefreshing: Bool = false
    public private(set) var isLoadingMore: Bool = false
    public private(set) var errorMessage: String?
    public var searchQuery: String = ""
    /// Exposed for `StalenessIndicator` in the toolbar.
    public var lastSyncedAt: Date?

    // MARK: - §5.1 Pagination

    /// Whether more pages are available.
    public private(set) var hasMore: Bool = false
    private var nextCursor: String?

    // MARK: - §5.1 Sort + Filter

    public var sortOrder: CustomerSortOrder = .name
    public var filter: CustomerListFilter = .init()

    // MARK: - §5.1 Stats header

    public private(set) var stats: CustomerListStats?
    public var showStats: Bool = false {
        didSet {
            Task { await load() }
        }
    }

    // MARK: - §5.1 Bulk select

    public var isBulkSelecting: Bool = false
    public var selectedIds: Set<Int64> = []

    // MARK: - §5.4 Concurrent-edit banner

    /// Set when a 409 response is received on an edit.
    public private(set) var concurrentEditConflict: Bool = false

    // MARK: - Dependencies

    @ObservationIgnored private let repo: CustomerRepository
    @ObservationIgnored private let cachedRepo: CustomerCachedRepository?
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    public init(repo: CustomerRepository) {
        self.repo = repo
        self.cachedRepo = repo as? CustomerCachedRepository
    }

    // MARK: - Load / refresh

    public func load() async {
        if customers.isEmpty { isLoading = true }
        defer { isLoading = false; isRefreshing = false }
        nextCursor = nil
        await fetchPage(cursor: nil, replacing: true)
    }

    /// Called by `.refreshable` — always hits remote when cache-aware.
    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        nextCursor = nil
        if let cached = cachedRepo {
            do {
                let results = try await cached.forceRefresh(
                    keyword: searchQuery.isEmpty ? nil : searchQuery
                )
                customers = results
                lastSyncedAt = await cached.lastSyncedAt
            } catch {
                AppLog.ui.error("Customer force-refresh failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        } else {
            await fetchPage(cursor: nil, replacing: true)
        }
    }

    // MARK: - §5.1 Cursor pagination

    /// Called when the list scrolls near the bottom.
    public func loadMoreIfNeeded(currentItem: CustomerSummary) async {
        guard !isLoadingMore, hasMore, let cursor = nextCursor else { return }
        guard let idx = customers.firstIndex(where: { $0.id == currentItem.id }) else { return }
        // Trigger when within 10 rows of the end.
        let threshold = max(0, customers.count - 10)
        guard idx >= threshold else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        await fetchPage(cursor: cursor, replacing: false)
    }

    // MARK: - Search

    public func onSearchChange(_ query: String) {
        searchQuery = query
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await load()
        }
    }

    // MARK: - §5.1 Bulk operations

    public func toggleBulkSelect() {
        isBulkSelecting.toggle()
        if !isBulkSelecting { selectedIds.removeAll() }
    }

    public func toggleSelection(id: Int64) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    public func bulkTag(tag: String) async {
        guard !selectedIds.isEmpty else { return }
        let req = BulkTagRequest(customerIds: Array(selectedIds), tag: tag)
        do {
            try await repo.bulkTag(req)
            isBulkSelecting = false
            selectedIds.removeAll()
            await load()
        } catch {
            AppLog.ui.error("Bulk tag failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    /// Returns a list of customers to be deleted (for undo display), then deletes.
    public func bulkDelete() async -> [CustomerSummary] {
        guard !selectedIds.isEmpty else { return [] }
        let toDelete = customers.filter { selectedIds.contains($0.id) }
        let req = BulkDeleteRequest(customerIds: Array(selectedIds))
        do {
            try await repo.bulkDelete(req)
            // Optimistic: remove from local list immediately.
            customers.removeAll { selectedIds.contains($0.id) }
            isBulkSelecting = false
            selectedIds.removeAll()
        } catch {
            AppLog.ui.error("Bulk delete failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
        return toDelete
    }

    /// Undo: restore deleted customers to list and re-fetch to get server state.
    public func undoBulkDelete(restored: [CustomerSummary]) async {
        // Restore optimistically, then re-fetch to sync.
        customers.insert(contentsOf: restored, at: 0)
        await load()
    }

    // MARK: - §5.4 Concurrent-edit

    public func dismissConflictBanner() {
        concurrentEditConflict = false
    }

    public func reportConcurrentEdit() {
        concurrentEditConflict = true
    }

    // MARK: - Private

    private func fetchPage(cursor: String?, replacing: Bool) async {
        errorMessage = nil
        let q = CustomerListQuery(
            keyword: searchQuery.isEmpty ? nil : searchQuery,
            sort: sortOrder.serverKey,
            ltvTier: filter.ltvTier,
            healthBand: filter.healthBand,
            balanceGtZero: filter.balanceGtZero,
            hasOpenTickets: filter.hasOpenTickets,
            city: filter.city,
            state: filter.state,
            tag: filter.tag,
            includeStats: showStats
        )
        do {
            let page = try await repo.listPage(cursor: cursor, query: q)
            if replacing {
                customers = page.customers
            } else {
                customers.append(contentsOf: page.customers)
            }
            nextCursor = page.nextCursor
            hasMore = page.nextCursor != nil
            if showStats { stats = page.stats }
            lastSyncedAt = Date()
        } catch {
            // If cursor pagination not supported by server, fall back to legacy list.
            AppLog.ui.debug(
                "Cursor list failed (\(error.localizedDescription, privacy: .public)), falling back to legacy list"
            )
            do {
                customers = try await repo.list(keyword: searchQuery.isEmpty ? nil : searchQuery)
                hasMore = false
                nextCursor = nil
                lastSyncedAt = Date()
            } catch let legacyErr {
                AppLog.ui.error("Customer list load failed: \(legacyErr.localizedDescription, privacy: .public)")
                errorMessage = legacyErr.localizedDescription
            }
        }
    }
}

// MARK: - Sort server key mapping

extension CustomerSortOrder {
    /// Maps the UI sort enum to the server `sort` query param value.
    var serverKey: String {
        switch self {
        case .name:         return "name_asc"
        case .nameDesc:     return "name_desc"
        case .mostTickets:  return "tickets_desc"
        case .mostRevenue:  return "revenue_desc"
        case .lastVisit:    return "last_visit_desc"
        case .ltvTier:      return "ltv_desc"
        case .churnRisk:    return "churn_desc"
        }
    }
}
