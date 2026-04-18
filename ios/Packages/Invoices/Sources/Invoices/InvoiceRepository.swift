import Foundation
import Networking

public protocol InvoiceRepository: Sendable {
    func list(filter: InvoiceFilter, keyword: String?) async throws -> [InvoiceSummary]
}

public actor InvoiceRepositoryImpl: InvoiceRepository {
    private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func list(filter: InvoiceFilter, keyword: String?) async throws -> [InvoiceSummary] {
        try await api.listInvoices(filter: filter, keyword: keyword).invoices
    }
}
