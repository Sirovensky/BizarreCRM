import Foundation
import Observation
import Core
import Networking
import Sync

@MainActor
@Observable
public final class InventoryListViewModel {
    public private(set) var items: [InventoryListItem] = []
    public private(set) var isLoading: Bool = false
    public private(set) var isRefreshing: Bool = false
    public private(set) var errorMessage: String?
    public var filter: InventoryFilter = .all
    public var sort: InventorySortOption = .nameAsc
    public var advanced: InventoryAdvancedFilter = .init()
    public var searchQuery: String = ""

    // Phase-3: staleness + offline
    public private(set) var lastSyncedAt: Date?
    public var isOffline: Bool = false

    // Indicates at least one advanced filter is active (drives filter-drawer badge).
    public var hasActiveAdvancedFilters: Bool { !advanced.isEmpty }

    @ObservationIgnored private let repo: InventoryRepository
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    public init(repo: InventoryRepository) {
        self.repo = repo
    }

    public func load() async {
        if items.isEmpty { isLoading = true }
        defer { isLoading = false; isRefreshing = false }
        await fetch(forceRemote: false)
    }

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await fetch(forceRemote: true)
    }

    public func applyFilter(_ newFilter: InventoryFilter) async {
        filter = newFilter
        await fetch(forceRemote: false)
    }

    public func applySort(_ newSort: InventorySortOption) async {
        sort = newSort
        await fetch(forceRemote: false)
    }

    public func applyAdvanced(_ newAdvanced: InventoryAdvancedFilter) async {
        advanced = newAdvanced
        await fetch(forceRemote: false)
    }

    public func onSearchChange(_ query: String) {
        searchQuery = query
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await fetch(forceRemote: false)
        }
    }

    private func fetch(forceRemote: Bool) async {
        errorMessage = nil
        let keyword = searchQuery.isEmpty ? nil : searchQuery
        do {
            if let cached = repo as? InventoryCachedRepositoryImpl {
                let result: CachedResult<[InventoryListItem]>
                if forceRemote {
                    result = try await cached.forceRefresh(
                        filter: filter,
                        sort: sort,
                        advanced: advanced,
                        keyword: keyword
                    )
                } else {
                    result = try await cached.cachedList(
                        filter: filter,
                        sort: sort,
                        advanced: advanced,
                        keyword: keyword
                    )
                }
                items = result.value
                lastSyncedAt = result.lastSyncedAt
            } else {
                items = try await repo.listAdvanced(
                    filter: filter,
                    sort: sort,
                    advanced: advanced,
                    keyword: keyword
                )
            }
        } catch {
            AppLog.ui.error("Inventory list load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}
