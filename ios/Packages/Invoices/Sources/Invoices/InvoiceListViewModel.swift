import Foundation
import Observation
import Core
import Networking
import Sync

// §7.1 Invoice list ViewModel
// Adds: status tabs, sort, bulk select, cursor pagination

@MainActor
@Observable
public final class InvoiceListViewModel {
    // MARK: - Data

    public private(set) var invoices: [InvoiceSummary] = []
    public private(set) var isLoading: Bool = false
    public private(set) var isRefreshing: Bool = false
    public private(set) var errorMessage: String?

    // MARK: - Filter / sort

    /// Legacy single-filter (kept for backward compat with InvoiceCachedRepositoryImpl.cachedList).
    public var filter: InvoiceFilter = .all

    /// Full status-tab set including Void.
    public var statusTab: InvoiceStatusTab = .all {
        didSet {
            filter = statusTab.legacyFilter
        }
    }

    public var sort: InvoiceSortOption = .dateDesc
    public var searchQuery: String = ""

    // MARK: - Bulk selection

    public var isBulkMode: Bool = false
    public private(set) var selectedIds: Set<Int64> = []

    public var isAllSelected: Bool {
        !invoices.isEmpty && selectedIds.count == invoices.count
    }

    // MARK: - Cursor pagination

    private var nextCursor: String?
    public private(set) var hasMore: Bool = false
    public private(set) var isLoadingMore: Bool = false

    // MARK: - Staleness / offline

    public private(set) var lastSyncedAt: Date?
    public var isOffline: Bool = false

    // MARK: - Deps

    @ObservationIgnored private let repo: InvoiceRepository
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    public init(repo: InvoiceRepository) { self.repo = repo }

    // MARK: - Load / refresh

    public func load() async {
        if invoices.isEmpty { isLoading = true }
        defer { isLoading = false; isRefreshing = false }
        nextCursor = nil
        await fetch(forceRemote: false)
    }

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        nextCursor = nil
        await fetch(forceRemote: true)
    }

    public func loadMore() async {
        guard hasMore, let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let response = try await repo.listExtended(
                statusTab: statusTab,
                keyword: searchQuery.isEmpty ? nil : searchQuery,
                sort: sort,
                cursor: cursor
            )
            invoices.append(contentsOf: response.invoices)
            nextCursor = response.pagination?.page.map { String($0 + 1) }
            hasMore = (response.pagination?.totalPages).map { $0 > (response.pagination?.page ?? 0) } ?? false
        } catch {
            AppLog.ui.error("Invoice load-more failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Filter / sort

    public func applyFilter(_ new: InvoiceFilter) async {
        filter = new
        await fetch(forceRemote: false)
    }

    public func applyStatusTab(_ tab: InvoiceStatusTab) async {
        statusTab = tab
        nextCursor = nil
        await fetch(forceRemote: false)
    }

    public func applySort(_ new: InvoiceSortOption) async {
        sort = new
        nextCursor = nil
        await fetch(forceRemote: false)
    }

    public func onSearchChange(_ query: String) {
        searchQuery = query
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            nextCursor = nil
            await fetch(forceRemote: false)
        }
    }

    // MARK: - Bulk selection

    public func toggleBulkMode() {
        isBulkMode.toggle()
        if !isBulkMode { selectedIds.removeAll() }
    }

    public func toggleSelection(id: Int64) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    public func selectAll() {
        selectedIds = Set(invoices.map(\.id))
    }

    public func deselectAll() {
        selectedIds.removeAll()
    }

    // MARK: - Private fetch

    private func fetch(forceRemote: Bool) async {
        errorMessage = nil
        do {
            if let cached = repo as? InvoiceCachedRepositoryImpl {
                let result: CachedResult<[InvoiceSummary]>
                if forceRemote {
                    result = try await cached.forceRefresh(
                        filter: statusTab.legacyFilter,
                        keyword: searchQuery.isEmpty ? nil : searchQuery
                    )
                } else {
                    result = try await cached.cachedList(
                        filter: statusTab.legacyFilter,
                        keyword: searchQuery.isEmpty ? nil : searchQuery
                    )
                }
                invoices = result.value
                lastSyncedAt = result.lastSyncedAt
            } else {
                let response = try await repo.listExtended(
                    statusTab: statusTab,
                    keyword: searchQuery.isEmpty ? nil : searchQuery,
                    sort: sort,
                    cursor: nil
                )
                invoices = response.invoices
                nextCursor = response.pagination?.page.map { String($0 + 1) }
                hasMore = (response.pagination?.totalPages).map { $0 > (response.pagination?.page ?? 0) } ?? false
            }
        } catch {
            AppLog.ui.error("Invoice list load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}
