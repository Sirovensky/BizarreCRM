import Foundation

/// `GET /api/v1/settings/statuses`. Server returns the raw
/// `ticket_statuses` row ordered by `sort_order` ascending. Fields we
/// consume are a subset — add more here if the UI needs them.
public struct TicketStatusRow: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let name: String
    public let sortOrder: Int?
    public let isClosed: Int?
    public let isCancelled: Int?
    public let notifyCustomer: Int?
    public let colorHex: String?

    public var closed: Bool    { (isClosed ?? 0) != 0 }
    public var cancelled: Bool { (isCancelled ?? 0) != 0 }

    enum CodingKeys: String, CodingKey {
        case id, name
        case sortOrder = "sort_order"
        case isClosed = "is_closed"
        case isCancelled = "is_cancelled"
        case notifyCustomer = "notify_customer"
        case colorHex = "color"
    }
}

/// `PATCH /api/v1/tickets/:id/status` body shape.
public struct ChangeTicketStatusRequest: Encodable, Sendable {
    public let statusId: Int64
    public init(statusId: Int64) { self.statusId = statusId }

    enum CodingKeys: String, CodingKey {
        case statusId = "status_id"
    }
}

public extension APIClient {
    func listTicketStatuses() async throws -> [TicketStatusRow] {
        try await get("/api/v1/settings/statuses", as: [TicketStatusRow].self)
    }

    /// Server returns the mutated ticket row; we only need the ID since
    /// the caller always re-fetches `TicketDetail` after a status change
    /// to pick up the audit log entry.
    func changeTicketStatus(id: Int64, statusId: Int64) async throws -> CreatedResource {
        try await patch(
            "/api/v1/tickets/\(id)/status",
            body: ChangeTicketStatusRequest(statusId: statusId),
            as: CreatedResource.self
        )
    }
}
