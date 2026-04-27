import Foundation
import Networking

public protocol TicketRepository: Sendable {
    func list(filter: TicketListFilter, keyword: String?, sort: TicketSortOrder) async throws -> [TicketSummary]
    func detail(id: Int64) async throws -> TicketDetail
    func delete(id: Int64) async throws
    func duplicate(id: Int64) async throws -> DuplicateTicketResponse
    func convertToInvoice(id: Int64) async throws -> ConvertToInvoiceResponse
}

public extension TicketRepository {
    /// Backwards-compatible default overload — filters/sort optional.
    func list(filter: TicketListFilter = .all, keyword: String? = nil) async throws -> [TicketSummary] {
        try await list(filter: filter, keyword: keyword, sort: .newest)
    }
}

public actor TicketRepositoryImpl: TicketRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func list(filter: TicketListFilter, keyword: String?, sort: TicketSortOrder) async throws -> [TicketSummary] {
        try await api.listTickets(filter: filter, keyword: keyword, sort: sort).tickets
    }

    public func detail(id: Int64) async throws -> TicketDetail {
        try await api.ticket(id: id)
    }

    public func delete(id: Int64) async throws {
        try await api.deleteTicket(ticketId: id)
    }

    public func duplicate(id: Int64) async throws -> DuplicateTicketResponse {
        try await api.duplicateTicket(ticketId: id)
    }

    public func convertToInvoice(id: Int64) async throws -> ConvertToInvoiceResponse {
        try await api.convertTicketToInvoice(ticketId: id)
    }
}
