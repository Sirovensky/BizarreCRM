import Foundation
import Networking

/// Network helpers for the `/activity` server endpoint.
///
/// Route confirmed in `packages/server/src/routes/activity.routes.ts` (SCAN-488).
/// Method: GET /activity
/// Auth:   authMiddleware applied at parent mount — standard Bearer token.
/// Authz:  admin / manager / superadmin may filter by any actor_user_id.
///         Non-manager roles are forced to their own events by the server.
///
/// Query params (all optional):
///   entity_kind    – e.g. "ticket", "customer", "invoice"
///   actor_user_id  – numeric user ID (admin / manager only on server side)
///   cursor         – cursor pagination (numeric last ID)
///   limit          – page size (server default 25, max 100)
public extension APIClient {

    /// Fetch a page of activity/audit log entries.
    ///
    /// - Parameters:
    ///   - actor:       Filter by actor user ID (admin/manager only on server).
    ///   - entityKind:  Filter by entity kind e.g. "ticket", "customer".
    ///   - since:       Start of date range — client-side post-filter only;
    ///                  the server does not accept date params on this endpoint.
    ///   - until:       End of date range — client-side post-filter only.
    ///   - cursor:      Cursor from a previous page's `next_cursor` value.
    ///   - limit:       Page size (1-100; server clamps to 100).
    func fetchAuditLogs(
        actor: String? = nil,
        entityKind: String? = nil,
        since: Date? = nil,
        until: Date? = nil,
        cursor: String? = nil,
        limit: Int? = nil
    ) async throws -> AuditLogPage {
        var items: [URLQueryItem] = []
        if let actor      { items.append(.init(name: "actor_user_id", value: actor)) }
        if let entityKind { items.append(.init(name: "entity_kind",   value: entityKind)) }
        if let cursor     { items.append(.init(name: "cursor",        value: cursor)) }
        if let limit      { items.append(.init(name: "limit",         value: String(limit))) }
        // Note: `since` / `until` are not server-supported query params on this
        // endpoint — the repository applies them as client-side filters after fetch.

        return try await get("/activity", query: items.isEmpty ? nil : items, as: AuditLogPage.self)
    }
}
