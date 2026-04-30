import Foundation
import Networking

// §7.1 InvoiceRepository — extended for status tabs, sort, cursor pagination, advanced filter

public protocol InvoiceRepository: Sendable {
    func list(filter: InvoiceFilter, keyword: String?) async throws -> [InvoiceSummary]
    func listExtended(
        statusTab: InvoiceStatusTab,
        keyword: String?,
        sort: InvoiceSortOption,
        cursor: String?,
        advancedFilter: InvoiceListFilter
    ) async throws -> InvoicesListResponse
}

public extension InvoiceRepository {
    /// Convenience overload without advancedFilter (defaults to empty).
    func listExtended(
        statusTab: InvoiceStatusTab,
        keyword: String?,
        sort: InvoiceSortOption,
        cursor: String?
    ) async throws -> InvoicesListResponse {
        try await listExtended(
            statusTab: statusTab,
            keyword: keyword,
            sort: sort,
            cursor: cursor,
            advancedFilter: InvoiceListFilter()
        )
    }
}

public actor InvoiceRepositoryImpl: InvoiceRepository {
    private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func list(filter: InvoiceFilter, keyword: String?) async throws -> [InvoiceSummary] {
        try await api.listInvoices(filter: filter, keyword: keyword).invoices
    }

    public func listExtended(
        statusTab: InvoiceStatusTab,
        keyword: String?,
        sort: InvoiceSortOption,
        cursor: String?,
        advancedFilter: InvoiceListFilter
    ) async throws -> InvoicesListResponse {
        try await api.listInvoices(
            filter: statusTab.legacyFilter,
            keyword: keyword,
            cursor: cursor,
            sort: sort.rawValue,
            statusOverride: statusTab.serverStatus,
            extraQueryItems: advancedFilter.queryItems
        )
    }
}
