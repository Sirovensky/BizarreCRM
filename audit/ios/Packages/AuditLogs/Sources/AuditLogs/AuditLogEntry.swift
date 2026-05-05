import Foundation

/// A single activity/audit event returned by `GET /activity`.
///
/// Maps to the `activity_events` table joined with `users`.
/// Server route: `packages/server/src/routes/activity.routes.ts` (SCAN-488).
/// Envelope: `{ success, data: { events: [...], next_cursor: String? } }`.
public struct AuditLogEntry: Identifiable, Codable, Sendable, Hashable {
    /// Numeric row ID — exposed as `String` for Identifiable convenience.
    public let id: String
    public let createdAt: Date
    /// `actor_user_id` from the event row — nil for system-generated events.
    public let actorUserId: Int?
    /// First name from the joined `users` row; nil for system events.
    public let actorFirstName: String?
    /// Last name from the joined `users` row; nil for system events.
    public let actorLastName: String?
    /// Action string e.g. "ticket.update", "customer.delete".
    public let action: String
    /// Entity kind e.g. "ticket", "customer", "invoice" (`entity_kind` column).
    public let entityKind: String
    /// Numeric entity ID; nil when the event is not tied to a specific record.
    public let entityId: Int?
    /// Scrubbed metadata dict — only safe keys are returned by the server (SCAN-506).
    public let metadata: [String: AuditDiffValue]?

    // MARK: Computed helpers

    /// Display-friendly actor name.  Falls back to "System" when actor is nil.
    public var actorName: String {
        let parts = [actorFirstName, actorLastName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "System" : parts.joined(separator: " ")
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt     = "created_at"
        case actorUserId   = "actor_user_id"
        case actorFirstName = "actor_first_name"
        case actorLastName  = "actor_last_name"
        case action
        case entityKind    = "entity_kind"
        case entityId      = "entity_id"
        case metadata
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Server returns `id` as an integer row id.
        let numericId = try c.decode(Int.self, forKey: .id)
        id             = String(numericId)
        createdAt      = try c.decode(Date.self, forKey: .createdAt)
        actorUserId    = try c.decodeIfPresent(Int.self, forKey: .actorUserId)
        actorFirstName = try c.decodeIfPresent(String.self, forKey: .actorFirstName)
        actorLastName  = try c.decodeIfPresent(String.self, forKey: .actorLastName)
        action         = try c.decode(String.self, forKey: .action)
        entityKind     = try c.decode(String.self, forKey: .entityKind)
        entityId       = try c.decodeIfPresent(Int.self, forKey: .entityId)
        metadata       = try c.decodeIfPresent([String: AuditDiffValue].self, forKey: .metadata)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // Re-encode id as Int for round-trip fidelity (tests / mocks may need this).
        try c.encode(Int(id) ?? 0, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(actorUserId, forKey: .actorUserId)
        try c.encodeIfPresent(actorFirstName, forKey: .actorFirstName)
        try c.encodeIfPresent(actorLastName, forKey: .actorLastName)
        try c.encode(action, forKey: .action)
        try c.encode(entityKind, forKey: .entityKind)
        try c.encodeIfPresent(entityId, forKey: .entityId)
        try c.encodeIfPresent(metadata, forKey: .metadata)
    }

    // MARK: Public memberwise init (for tests / mocks)

    public init(
        id: String,
        createdAt: Date,
        actorUserId: Int? = nil,
        actorFirstName: String? = nil,
        actorLastName: String? = nil,
        action: String,
        entityKind: String,
        entityId: Int? = nil,
        metadata: [String: AuditDiffValue]? = nil
    ) {
        self.id             = id
        self.createdAt      = createdAt
        self.actorUserId    = actorUserId
        self.actorFirstName = actorFirstName
        self.actorLastName  = actorLastName
        self.action         = action
        self.entityKind     = entityKind
        self.entityId       = entityId
        self.metadata       = metadata
    }
}

/// Paginated list envelope — contents of `data` from `GET /activity`.
///
/// Server shape: `{ events: [...], next_cursor: String? }`.
public struct AuditLogPage: Decodable, Sendable {
    public let entries: [AuditLogEntry]
    public let nextCursor: String?

    public init(entries: [AuditLogEntry], nextCursor: String?) {
        self.entries   = entries
        self.nextCursor = nextCursor
    }

    private enum CodingKeys: String, CodingKey {
        case entries   = "events"
        case nextCursor = "next_cursor"
    }
}
