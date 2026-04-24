import Foundation
import Networking

public protocol CustomerRepository: Sendable {
    func list(keyword: String?) async throws -> [CustomerSummary]

    /// `PUT /api/v1/customers/:id` — update editable fields and return the
    /// refreshed detail snapshot.  On success the caller should replace its
    /// local `CustomerDetail` with the returned value.
    func update(id: Int64, _ req: UpdateCustomerRequest) async throws -> CustomerDetail
}

public actor CustomerRepositoryImpl: CustomerRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func list(keyword: String?) async throws -> [CustomerSummary] {
        try await api.listCustomers(keyword: keyword).customers
    }

    public func update(id: Int64, _ req: UpdateCustomerRequest) async throws -> CustomerDetail {
        try await api.updateCustomerDetail(id: id, req)
    }
}
