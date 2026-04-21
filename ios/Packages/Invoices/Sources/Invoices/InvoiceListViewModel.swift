import Foundation
import Observation
import Core
import Networking
import Sync

@MainActor
@Observable
public final class InvoiceListViewModel {
    public private(set) var invoices: [InvoiceSummary] = []
    public private(set) var isLoading: Bool = false
    public private(set) var isRefreshing: Bool = false
    public private(set) var errorMessage: String?
    public var filter: InvoiceFilter = .all
    public var searchQuery: String = ""

    // Phase-3: staleness + offline
    public private(set) var lastSyncedAt: Date?
    public var isOffline: Bool = false

    @ObservationIgnored private let repo: InvoiceRepository
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    public init(repo: InvoiceRepository) { self.repo = repo }

    public func load() async {
        if invoices.isEmpty { isLoading = true }
        defer { isLoading = false; isRefreshing = false }
        await fetch(forceRemote: false)
    }

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await fetch(forceRemote: true)
    }

    public func applyFilter(_ new: InvoiceFilter) async {
        filter = new
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
        do {
            if let cached = repo as? InvoiceCachedRepositoryImpl {
                let result: CachedResult<[InvoiceSummary]>
                if forceRemote {
                    result = try await cached.forceRefresh(
                        filter: filter,
                        keyword: searchQuery.isEmpty ? nil : searchQuery
                    )
                } else {
                    result = try await cached.cachedList(
                        filter: filter,
                        keyword: searchQuery.isEmpty ? nil : searchQuery
                    )
                }
                invoices = result.value
                lastSyncedAt = result.lastSyncedAt
            } else {
                invoices = try await repo.list(
                    filter: filter,
                    keyword: searchQuery.isEmpty ? nil : searchQuery
                )
            }
        } catch {
            AppLog.ui.error("Invoice list load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}
