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

    @ObservationIgnored private let repo: CustomerRepository
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    public init(repo: CustomerRepository) {
        self.repo = repo
    }

    public func load() async {
        if customers.isEmpty { isLoading = true }
        defer { isLoading = false; isRefreshing = false }
        await fetch()
    }

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
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
            customers = try await repo.list(keyword: searchQuery.isEmpty ? nil : searchQuery)
        } catch {
            AppLog.ui.error("Customer list load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}
