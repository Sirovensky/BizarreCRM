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

    @ObservationIgnored private let repo: TicketRepository
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    public init(repo: TicketRepository) {
        self.repo = repo
    }

    public func load() async {
        if tickets.isEmpty { isLoading = true }
        defer { isLoading = false; isRefreshing = false }
        await fetch()
    }

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await fetch()
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
        } catch {
            AppLog.ui.error("Ticket list load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}
