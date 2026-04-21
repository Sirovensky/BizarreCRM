import Foundation

private struct _TicketArchiveEmptyBody: Encodable, Sendable {}

// §4.7 — Timeline events endpoint
// Server route: GET /api/v1/tickets/:id/events
// Returns an array of `TicketEvent` entries representing the full audit
// trail for a ticket: status changes, notes, photo uploads, assignments,
// part orders, etc.

// MARK: - TicketEvent model

/// A single timeline entry from `GET /api/v1/tickets/:id/events`.
public struct TicketEvent: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let createdAt: String
    public let actorName: String?
    public let kind: EventKind
    public let message: String
    public let diff: [DiffEntry]?

    // MARK: — Event kind

    /// Structured event type. `unknown` is a safe fallback for future server values.
    public enum EventKind: String, Decodable, Sendable, Hashable {
        case statusChange   = "status_change"
        case noteAdded      = "note_added"
        case photoAdded     = "photo_added"
        case assigned       = "assigned"
        case partOrdered    = "part_ordered"
        case created        = "created"
        case invoiced       = "invoiced"
        case unknown

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = EventKind(rawValue: raw) ?? .unknown
        }

        /// SF Symbol name for this kind of event.
        public var systemImage: String {
            switch self {
            case .statusChange: return "arrow.right.circle"
            case .noteAdded:    return "text.bubble"
            case .photoAdded:   return "photo.fill"
            case .assigned:     return "person.crop.circle.fill.badge.plus"
            case .partOrdered:  return "cart.fill"
            case .created:      return "ticket.fill"
            case .invoiced:     return "doc.text.fill"
            case .unknown:      return "circle.fill"
            }
        }
    }

    // MARK: — Diff entry

    /// A single field change within an event (e.g. `{ field: "status", from: "Intake", to: "Diagnosing" }`).
    public struct DiffEntry: Decodable, Sendable, Hashable {
        public let field: String
        public let from: String?
        public let to: String?

        enum CodingKeys: String, CodingKey {
            case field, from, to
        }
    }

    // MARK: — Memberwise init (for testing + synthetic events)

    public init(
        id: Int64,
        createdAt: String,
        actorName: String?,
        kind: EventKind,
        message: String,
        diff: [DiffEntry]?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.actorName = actorName
        self.kind = kind
        self.message = message
        self.diff = diff
    }

    // MARK: — Coding keys

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt  = "created_at"
        case actorName  = "actor_name"
        case kind
        case message
        case diff
    }
}

// MARK: - Additional request types

/// `PATCH /api/v1/tickets/:id/assign` body.
public struct AssignTicketRequest: Encodable, Sendable {
    public let employeeId: Int64

    public init(employeeId: Int64) { self.employeeId = employeeId }

    enum CodingKeys: String, CodingKey {
        case employeeId = "employeeId"
    }
}

/// `POST /api/v1/tickets/:id/archive` — no body required.
public struct ArchiveTicketResponse: Decodable, Sendable {
    public let success: Bool
    public let message: String?
}

// MARK: - APIClient extensions

public extension APIClient {
    /// `GET /api/v1/tickets/:id/events` — full timeline for a ticket.
    func ticketEvents(id: Int64) async throws -> [TicketEvent] {
        try await get("/api/v1/tickets/\(id)/events", as: [TicketEvent].self)
    }

    /// `PATCH /api/v1/tickets/:id/assign` — reassign to a different employee.
    func assignTicket(id: Int64, employeeId: Int64) async throws -> CreatedResource {
        try await patch(
            "/api/v1/tickets/\(id)/assign",
            body: AssignTicketRequest(employeeId: employeeId),
            as: CreatedResource.self
        )
    }

    /// `POST /api/v1/tickets/:id/archive` — soft-archive a ticket.
    func archiveTicket(id: Int64) async throws -> ArchiveTicketResponse {
        return try await post(
            "/api/v1/tickets/\(id)/archive",
            body: _TicketArchiveEmptyBody(),
            as: ArchiveTicketResponse.self
        )
    }

    /// `PATCH /api/v1/tickets/:id/status` — update status via state machine
    /// transition label (convenience wrapper over `changeTicketStatus`).
    func updateTicketStatus(ticketId: Int64, statusId: Int64) async throws -> CreatedResource {
        try await changeTicketStatus(id: ticketId, statusId: statusId)
    }
}
