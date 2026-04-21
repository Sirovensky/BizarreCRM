import Foundation
import Networking

/// Network helpers for the `/audit-logs` server endpoint.
///
/// Server route: `GET /audit-logs?actor=&action=&entity=&since=&until=&cursor=&q=`
/// Confirmed in `packages/server/src/routes/audit.routes.ts`.
public extension APIClient {

    /// Fetch a page of audit log entries.
    ///
    /// - Parameters:
    ///   - actor:   Filter by actor ID string.
    ///   - action:  Filter by action string (e.g. "ticket.update").
    ///   - entity:  Filter by entity type (e.g. "ticket").
    ///   - since:   ISO-8601 start of date range.
    ///   - until:   ISO-8601 end of date range.
    ///   - cursor:  Opaque pagination cursor from a previous page response.
    ///   - q:       Free-text server-side search term.
    func fetchAuditLogs(
        actor: String? = nil,
        action: String? = nil,
        entity: String? = nil,
        since: Date? = nil,
        until: Date? = nil,
        cursor: String? = nil,
        q: String? = nil
    ) async throws -> AuditLogPage {
        let iso = ISO8601DateFormatter()
        var items: [URLQueryItem] = []
        if let actor  { items.append(.init(name: "actor",  value: actor)) }
        if let action { items.append(.init(name: "action", value: action)) }
        if let entity { items.append(.init(name: "entity", value: entity)) }
        if let since  { items.append(.init(name: "since",  value: iso.string(from: since))) }
        if let until  { items.append(.init(name: "until",  value: iso.string(from: until))) }
        if let cursor { items.append(.init(name: "cursor", value: cursor)) }
        if let q, !q.isEmpty { items.append(.init(name: "q", value: q)) }

        return try await get("/audit-logs", query: items.isEmpty ? nil : items, as: AuditLogPage.self)
    }
}
