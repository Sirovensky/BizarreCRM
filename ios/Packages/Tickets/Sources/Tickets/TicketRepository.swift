import Foundation
import Networking

public protocol TicketRepository: Sendable {
    func list(filter: TicketListFilter, keyword: String?) async throws -> [TicketSummary]
    func detail(id: Int64) async throws -> TicketDetail
}

public actor TicketRepositoryImpl: TicketRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func list(filter: TicketListFilter, keyword: String?) async throws -> [TicketSummary] {
        try await api.listTickets(filter: filter, keyword: keyword).tickets
    }

    public func detail(id: Int64) async throws -> TicketDetail {
        try await api.ticket(id: id)
    }
}
