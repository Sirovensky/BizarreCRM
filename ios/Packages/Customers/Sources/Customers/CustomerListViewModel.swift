import Foundation
import Observation
import Core
import Networking

@MainActor
@Observable
public final class CustomerListViewModel {
    public private(set) var customers: [CustomerSummary] = []
    public private(set) var isLoading: Bool = false
    public private(set) var isRefreshing: Bool = false
    public private(set) var errorMessage: String?
    public var searchQuery: String = ""
    /// Exposed for `StalenessIndicator` in the toolbar.
    public var lastSyncedAt: Date?

    @ObservationIgnored private let repo: CustomerRepository
    @ObservationIgnored private let cachedRepo: CustomerCachedRepository?
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    public init(repo: CustomerRepository) {
        self.repo = repo
        self.cachedRepo = repo as? CustomerCachedRepository
    }

    public func load() async {
        if customers.isEmpty { isLoading = true }
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
                    keyword: searchQuery.isEmpty ? nil : searchQuery
                )
                customers = results
                lastSyncedAt = await cached.lastSyncedAt
            } catch {
                AppLog.ui.error("Customer force-refresh failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        } else {
            await fetch()
        }
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
            customers = try await repo.list(keyword: searchQuery.isEmpty ? nil : searchQuery)
            if let cached = cachedRepo {
                lastSyncedAt = await cached.lastSyncedAt
            }
        } catch {
            AppLog.ui.error("Customer list load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}
