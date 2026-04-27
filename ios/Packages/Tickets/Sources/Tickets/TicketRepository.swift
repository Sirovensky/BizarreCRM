import Foundation
import Networking

public protocol TicketRepository: Sendable {
    /// §4.1: list with status-group + optional urgency filter.
    func list(filter: TicketListFilter, urgency: TicketUrgencyFilter?, keyword: String?) async throws -> [TicketSummary]
    func detail(id: Int64) async throws -> TicketDetail
}

public extension TicketRepository {
    /// Backward-compat overload — callers that omit urgency continue to compile.
    func list(filter: TicketListFilter, keyword: String?) async throws -> [TicketSummary] {
        try await list(filter: filter, urgency: nil, keyword: keyword)
    }
}

public actor TicketRepositoryImpl: TicketRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func list(filter: TicketListFilter, urgency: TicketUrgencyFilter?, keyword: String?) async throws -> [TicketSummary] {
        try await api.listTickets(filter: filter, urgency: urgency, keyword: keyword).tickets
    }

    public func detail(id: Int64) async throws -> TicketDetail {
        try await api.ticket(id: id)
    }
}
