import Foundation
import Networking

/// Repository that mediates between the network and the ViewModel.
///
/// The server's `GET /activity` endpoint supports filtering by `entity_kind`
/// and `actor_user_id`.  It does NOT support date-range params — those are
/// applied client-side here after each page fetch.
///
/// §50.10 offline cache: `cachedRecent()` returns empty — offline caching
/// deferred to a later sprint when GRDB SQLCipher wiring is added for
/// audit log entities. TODO: implement GRDB `ValueObservation` cache.
public actor AuditLogRepository {

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    /// Fetch the first page or a subsequent cursor page.
    ///
    /// Date-range filters (`since`/`until`) are applied client-side — the
    /// server does not accept them on this endpoint.  Query (`q`) and action
    /// multi-select are also client-side because the server has no such params.
    public func fetch(filters: AuditLogFilters, cursor: String? = nil) async throws -> AuditLogPage {
        let page = try await api.fetchAuditLogs(
            actor:      filters.actorId,
            entityKind: filters.entityType,
            cursor:     cursor
        )

        // Client-side post-filtering for fields not supported as server params.
        let filtered = page.entries.filter { entry in
            if let since = filters.since, entry.createdAt < since { return false }
            if let until = filters.until, entry.createdAt > until { return false }
            if !filters.actions.isEmpty, !filters.actions.contains(entry.action) { return false }
            let q = filters.query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !q.isEmpty {
                let haystack = "\(entry.actorName) \(entry.action) \(entry.entityKind)".lowercased()
                if !haystack.contains(q.lowercased()) { return false }
            }
            return true
        }

        return AuditLogPage(entries: filtered, nextCursor: page.nextCursor)
    }

    /// §50.10 stub — offline cache not yet implemented.
    /// Returns empty array; caller shows the live-only fallback state.
    public func cachedRecent() -> [AuditLogEntry] {
        // TODO: read from GRDB AuditLogs table when offline caching is wired.
        []
    }
}
