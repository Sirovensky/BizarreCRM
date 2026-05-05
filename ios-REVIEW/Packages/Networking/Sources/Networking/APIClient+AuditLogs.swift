import Foundation

/// Networking-layer extension for the audit / activity feed.
///
/// Route confirmed: GET /activity (activity.routes.ts, SCAN-488).
/// Envelope: `{ success: Bool, data: { events: [...], next_cursor: String? } }`.
/// Auth: Bearer token via authMiddleware applied at parent mount in index.ts.
///
/// NOTE: This extension declares the raw `fetchActivityPage` primitive.
/// The AuditLogs package vends `fetchAuditLogs(...)` on top of this via
/// `AuditLogEndpoints.swift`, which owns the `AuditLogPage` model.
/// This file is append-only — add new activity/audit endpoints below.
public extension APIClient {

    /// Low-level fetch of a page of activity events.
    ///
    /// Prefer `AuditLogEndpoints.fetchAuditLogs(...)` from the AuditLogs
    /// package unless you need a lower-level call without the model layer.
    ///
    /// - Parameters:
    ///   - actorUserId: Filter by numeric user ID (admin/manager only on server).
    ///   - entityKind:  Filter by entity kind e.g. "ticket", "customer".
    ///   - cursor:      Pagination cursor — numeric last row ID from previous page.
    ///   - limit:       Page size 1–100; server default 25, max 100.
    /// - Returns: Raw `Decodable` type `T` decoded from inside the `data` envelope.
    func fetchActivityPage<T: Decodable & Sendable>(
        actorUserId: Int? = nil,
        entityKind: String? = nil,
        cursor: Int? = nil,
        limit: Int? = nil,
        as type: T.Type
    ) async throws -> T {
        var items: [URLQueryItem] = []
        if let actorUserId { items.append(.init(name: "actor_user_id", value: String(actorUserId))) }
        if let entityKind  { items.append(.init(name: "entity_kind",   value: entityKind)) }
        if let cursor      { items.append(.init(name: "cursor",        value: String(cursor))) }
        if let limit       { items.append(.init(name: "limit",         value: String(limit))) }
        return try await get("/activity", query: items.isEmpty ? nil : items, as: type)
    }
}
