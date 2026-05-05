import Foundation
import Networking

// MARK: - BulkAction

/// The set of bulk operations the server supports at
/// `POST /api/v1/tickets/bulk-action`.
///
/// Server route: packages/server/src/routes/tickets.routes.ts:3555
/// Validated actions: change_status | assign | delete
public enum BulkAction: Sendable {
    /// `change_status` — value is the target status ID.
    case changeStatus(statusId: Int64)
    /// `assign` — value is the assignee user ID; nil = unassign.
    case reassign(userId: Int64?)
    /// `delete` — admin-only, soft-deletes tickets and restores inventory.
    case archive

    /// Wire-format action string sent to the server.
    public var actionKey: String {
        switch self {
        case .changeStatus: return "change_status"
        case .reassign:     return "assign"
        case .archive:      return "delete"
        }
    }

    /// Optional `value` field for the server body.
    public var value: Int64? {
        switch self {
        case .changeStatus(let id): return id
        case .reassign(let id):     return id
        case .archive:              return nil
        }
    }
}

// MARK: - BulkActionRequest / Response

/// `POST /api/v1/tickets/bulk-action` body.
/// Server enforces: ticket_ids.length 1–100, action in validActions.
struct BulkActionRequest: Encodable, Sendable {
    let ticketIds: [Int64]
    let action: String
    let value: Int64?

    enum CodingKeys: String, CodingKey {
        case ticketIds = "ticket_ids"
        case action
        case value
    }
}

/// `data` field inside the `{ success, data, message }` envelope.
/// Server returns `{ affected: number, ticket_ids: number[] }`.
public struct BulkActionData: Decodable, Sendable {
    public let affected: Int
    public let ticketIds: [Int64]

    public init(affected: Int, ticketIds: [Int64]) {
        self.affected = affected
        self.ticketIds = ticketIds
    }

    enum CodingKeys: String, CodingKey {
        case affected
        case ticketIds = "ticket_ids"
    }
}

// MARK: - Per-ticket outcome (used by coordinator & result view)

/// Outcome for a single ticket in a batch.
public struct BulkTicketOutcome: Sendable, Identifiable {
    public let id: Int64
    public enum Status: Sendable {
        case succeeded
        case failed(message: String)
    }
    public let status: Status

    public var succeeded: Bool {
        if case .succeeded = status { return true }
        return false
    }

    public init(id: Int64, status: Status) {
        self.id = id
        self.status = status
    }
}
