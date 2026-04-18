import Foundation
import Observation
import Core
import Networking

@MainActor
@Observable
public final class InvoiceListViewModel {
    public private(set) var invoices: [InvoiceSummary] = []
    public private(set) var isLoading: Bool = false
    public private(set) var isRefreshing: Bool = false
    public private(set) var errorMessage: String?
    public var filter: InvoiceFilter = .all
    public var searchQuery: String = ""

    @ObservationIgnored private let repo: InvoiceRepository
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    public init(repo: InvoiceRepository) { self.repo = repo }

    public func load() async {
        if invoices.isEmpty { isLoading = true }
        defer { isLoading = false; isRefreshing = false }
        await fetch()
    }

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await fetch()
    }

    public func applyFilter(_ new: InvoiceFilter) async {
        filter = new
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
            invoices = try await repo.list(filter: filter, keyword: searchQuery.isEmpty ? nil : searchQuery)
        } catch {
            AppLog.ui.error("Invoice list load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}
