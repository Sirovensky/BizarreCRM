import Foundation
import Networking

public protocol CustomerRepository: Sendable {
    func list(keyword: String?) async throws -> [CustomerSummary]

    /// Cursor-paginated fetch (§5.1). Returns a page of customers plus the next cursor.
    func listPage(cursor: String?, query: CustomerListQuery) async throws -> CustomerCursorPage

    /// `PUT /api/v1/customers/:id` — update editable fields and return the
    /// refreshed detail snapshot.  On success the caller should replace its
    /// local `CustomerDetail` with the returned value.
    func update(id: Int64, _ req: UpdateCustomerRequest) async throws -> CustomerDetail

    /// `POST /api/v1/customers/bulk-tag` — apply a tag to many customers (§5.6).
    @discardableResult
    func bulkTag(_ req: BulkTagRequest) async throws -> BulkOperationResult

    /// `DELETE /api/v1/customers/bulk` — delete many customers (§5.6).
    @discardableResult
    func bulkDelete(_ req: BulkDeleteRequest) async throws -> BulkOperationResult
}

public actor CustomerRepositoryImpl: CustomerRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func list(keyword: String?) async throws -> [CustomerSummary] {
        try await api.listCustomers(keyword: keyword).customers
    }

    public func listPage(cursor: String?, query: CustomerListQuery) async throws -> CustomerCursorPage {
        try await api.listCustomersCursor(cursor: cursor, query: query)
    }

    public func update(id: Int64, _ req: UpdateCustomerRequest) async throws -> CustomerDetail {
        try await api.updateCustomerDetail(id: id, req)
    }

    public func bulkTag(_ req: BulkTagRequest) async throws -> BulkOperationResult {
        try await api.bulkTagCustomers(req)
    }

    public func bulkDelete(_ req: BulkDeleteRequest) async throws -> BulkOperationResult {
        try await api.bulkDeleteCustomers(req)
    }
}
