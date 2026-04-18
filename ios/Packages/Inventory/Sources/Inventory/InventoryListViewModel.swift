import Foundation
import Observation
import Core
import Networking

@MainActor
@Observable
public final class InventoryListViewModel {
    public private(set) var items: [InventoryListItem] = []
    public private(set) var isLoading: Bool = false
    public private(set) var isRefreshing: Bool = false
    public private(set) var errorMessage: String?
    public var filter: InventoryFilter = .all
    public var searchQuery: String = ""

    @ObservationIgnored private let repo: InventoryRepository
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    public init(repo: InventoryRepository) {
        self.repo = repo
    }

    public func load() async {
        if items.isEmpty { isLoading = true }
        defer { isLoading = false; isRefreshing = false }
        await fetch()
    }

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await fetch()
    }

    public func applyFilter(_ newFilter: InventoryFilter) async {
        filter = newFilter
        await fetch()
    }

    public func onSearchChange(_ query: String) {
        searchQuery = query
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await fetch()
        }
    }

    private func fetch() async {
        errorMessage = nil
        do {
            items = try await repo.list(filter: filter, keyword: searchQuery.isEmpty ? nil : searchQuery)
        } catch {
            AppLog.ui.error("Inventory list load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}
