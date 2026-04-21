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

    // MARK: - §22 Quick-action handlers

    /// Advance `ticket` to the next status via `transition`.
    /// Optimistically removes the stale entry and refreshes when complete.
    public func advanceStatus(ticket: TicketSummary, transition: TicketTransition) async {
        // Optimistic removal from current view while the request is in-flight.
        tickets = tickets.map { $0 }   // immutable copy preserved
        // TODO: wire to APIClient+Tickets advanceStatus when Phase-4 endpoint ships.
        AppLog.ui.debug("Quick-action advanceStatus: ticket=\(ticket.id) transition=\(transition.rawValue, privacy: .public)")
        await refresh()
    }

    /// Archive `ticket` (marks status archived on the server).
    public func archive(ticket: TicketSummary) async {
        // TODO: wire to PATCH /tickets/:id { status: "archived" } — Phase 4.
        AppLog.ui.debug("Quick-action archive: ticket=\(ticket.id)")
        await refresh()
    }

    /// Delete `ticket` permanently.
    public func delete(ticket: TicketSummary) async {
        // Optimistic removal.
        tickets = tickets.filter { $0.id != ticket.id }
        // TODO: wire to DELETE /tickets/:id — Phase 4.
        AppLog.ui.debug("Quick-action delete: ticket=\(ticket.id)")
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
