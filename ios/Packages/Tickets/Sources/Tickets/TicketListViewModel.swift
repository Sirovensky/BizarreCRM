import Foundation
import Observation
import Core
import Networking

@MainActor
@Observable
public final class TicketListViewModel {
    public private(set) var tickets: [TicketSummary] = []
    public private(set) var isLoading: Bool = false
    public private(set) var isRefreshing: Bool = false
    public private(set) var errorMessage: String?
    public var filter: TicketListFilter = .all
    public var searchQuery: String = ""
    /// Exposed for `StalenessIndicator` in the toolbar.
    public var lastSyncedAt: Date?

    @ObservationIgnored private let repo: TicketRepository
    @ObservationIgnored private let cachedRepo: TicketCachedRepository?
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    public init(repo: TicketRepository) {
        self.repo = repo
        self.cachedRepo = repo as? TicketCachedRepository
    }

    public func load() async {
        if tickets.isEmpty { isLoading = true }
        defer { isLoading = false; isRefreshing = false }
        await fetch()
    }

    /// Called by `.refreshable` — always hits remote when cache-aware.
    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        if let cached = cachedRepo {
            do {
                let results = try await cached.forceRefresh(
                    filter: filter,
                    keyword: searchQuery.isEmpty ? nil : searchQuery
                )
                tickets = results
                lastSyncedAt = await cached.lastSyncedAt
            } catch {
                AppLog.ui.error("Ticket force-refresh failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        } else {
            await fetch()
        }
    }

    public func applyFilter(_ newFilter: TicketListFilter) async {
        filter = newFilter
        await fetch()
    }

    /// Called on every keystroke from the search field. Debounces 300ms
    /// (matches Android TicketListScreen.kt:134) and then re-fetches.
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
            let results = try await repo.list(
                filter: filter,
                keyword: searchQuery.isEmpty ? nil : searchQuery
            )
            tickets = results
            if let cached = cachedRepo {
                lastSyncedAt = await cached.lastSyncedAt
            }
        } catch {
            AppLog.ui.error("Ticket list load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}
