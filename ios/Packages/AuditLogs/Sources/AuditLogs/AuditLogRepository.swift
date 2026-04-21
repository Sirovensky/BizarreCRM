import Foundation
import Networking

/// Repository that mediates between the network and the ViewModel.
/// §50.10 offline cache: `cachedRecent()` returns empty — offline caching
/// deferred to a later sprint when GRDB SQLCipher wiring is added for
/// audit log entities. TODO: implement GRDB `ValueObservation` cache.
public actor AuditLogRepository {

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    /// Fetch the first page or a subsequent cursor page.
    public func fetch(filters: AuditLogFilters, cursor: String? = nil) async throws -> AuditLogPage {
        try await api.fetchAuditLogs(
            actor:  filters.actorId,
            action: filters.actions.isEmpty ? nil : filters.actions.joined(separator: ","),
            entity: filters.entityType,
            since:  filters.since,
            until:  filters.until,
            cursor: cursor,
            q:      filters.query.isEmpty ? nil : filters.query
        )
    }

    /// §50.10 stub — offline cache not yet implemented.
    /// Returns empty array; caller shows the live-only fallback state.
    public func cachedRecent() -> [AuditLogEntry] {
        // TODO: read from GRDB AuditLogs table when offline caching is wired.
        []
    }
}
