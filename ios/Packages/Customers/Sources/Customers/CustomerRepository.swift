import Foundation
import Networking

public protocol CustomerRepository: Sendable {
    func list(keyword: String?) async throws -> [CustomerSummary]
}

public actor CustomerRepositoryImpl: CustomerRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func list(keyword: String?) async throws -> [CustomerSummary] {
        try await api.listCustomers(keyword: keyword).customers
    }
}
