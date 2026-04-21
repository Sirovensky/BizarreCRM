import Foundation

/// A single audit log record returned by `GET /audit-logs`.
public struct AuditLogEntry: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let createdAt: Date
    public let actorId: String
    public let actorName: String
    public let actorRole: String?
    /// Dot-namespaced action string e.g. "ticket.update", "customer.delete".
    public let action: String
    /// Affected entity type e.g. "ticket", "customer", "invoice".
    public let entityType: String
    public let entityId: String
    public let diff: AuditDiff?
    public let deviceFingerprint: String?

    public init(
        id: String,
        createdAt: Date,
        actorId: String,
        actorName: String,
        actorRole: String? = nil,
        action: String,
        entityType: String,
        entityId: String,
        diff: AuditDiff? = nil,
        deviceFingerprint: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.actorId = actorId
        self.actorName = actorName
        self.actorRole = actorRole
        self.action = action
        self.entityType = entityType
        self.entityId = entityId
        self.diff = diff
        self.deviceFingerprint = deviceFingerprint
    }
}

/// Paginated list envelope from the server.
public struct AuditLogPage: Decodable, Sendable {
    public let entries: [AuditLogEntry]
    public let nextCursor: String?

    public init(entries: [AuditLogEntry], nextCursor: String?) {
        self.entries = entries
        self.nextCursor = nextCursor
    }

    private enum CodingKeys: String, CodingKey {
        case entries, nextCursor
    }
}
