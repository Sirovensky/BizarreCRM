import Foundation
import Networking

// §7.1 InvoiceRepository — extended for status tabs, sort, cursor pagination

public protocol InvoiceRepository: Sendable {
    func list(filter: InvoiceFilter, keyword: String?) async throws -> [InvoiceSummary]
    func listExtended(
        statusTab: InvoiceStatusTab,
        keyword: String?,
        sort: InvoiceSortOption,
        cursor: String?
    ) async throws -> InvoicesListResponse
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
        cursor: String?
    ) async throws -> InvoicesListResponse {
        try await api.listInvoices(
            filter: statusTab.legacyFilter,
            keyword: keyword,
            cursor: cursor,
            sort: sort.rawValue,
            statusOverride: statusTab.serverStatus
        )
    }
}
