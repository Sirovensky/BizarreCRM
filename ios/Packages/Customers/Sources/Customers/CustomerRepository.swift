import Foundation
import Networking

public protocol CustomerRepository: Sendable {
    func list(keyword: String?) async throws -> [CustomerSummary]

    /// Cursor-paginated fetch (§5.1). Returns a page of customers plus the next cursor.
    func listPage(cursor: String?, query: CustomerListQuery) async throws -> CustomerCursorPage

    /// `POST /api/v1/customers` — create a new customer from a Contacts import candidate.
    func createFromContact(_ req: ContactImportCreateRequest) async throws

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

// MARK: - Contacts import request

public struct ContactImportCreateRequest: Encodable, Sendable {
    public let first_name: String
    public let last_name: String
    public let phone: String?
    public let email: String?
    public let organization: String?
    public let address1: String?

    public init(firstName: String, lastName: String, phone: String?, email: String?, organization: String?, address1: String?) {
        self.first_name = firstName
        self.last_name = lastName
        self.phone = phone
        self.email = email
        self.organization = organization
        self.address1 = address1
    }
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

    public func createFromContact(_ req: ContactImportCreateRequest) async throws {
        try await api.createCustomerFromContact(req)
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
