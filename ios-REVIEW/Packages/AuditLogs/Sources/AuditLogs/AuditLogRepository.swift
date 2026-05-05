import Foundation
import Networking

/// Repository that mediates between the network and the ViewModel.
///
/// The server's `GET /activity` endpoint supports filtering by `entity_kind`
/// and `actor_user_id`.  It does NOT support date-range params — those are
/// applied client-side here after each page fetch.
///
/// §50.10 offline cache: an in-memory write-through cache stores up to 90 days
/// of entries fetched during this session. Full GRDB/SQLCipher persistence is
/// deferred until the Persistence package wires the audit_logs table migration.
public actor AuditLogRepository {

    private let api: APIClient

    // §50.10 — in-memory write-through cache.
    // Stores the most recent `cacheCapacity` entries fetched from the server.
    // Survives app backgrounding within the same process lifecycle.
    private var cache: [AuditLogEntry] = []
    private let cacheCapacity = 500          // ~90d for active tenants
    private let cacheTTL: TimeInterval = 90 * 24 * 3600  // 90 days
    private var cacheLastUpdated: Date?

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

        // §50.10 — write fetched entries into the in-memory cache (first page only,
        // to avoid duplicates from pagination).
        if cursor == nil {
            mergeIntoCache(page.entries)
        }

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

    /// §50.10 — Return cached entries from the last 90 days, sorted newest-first.
    /// Falls back to empty when no entries have been fetched this session.
    /// GRDB persistence is the next step (TODO: Persistence migration audit_logs table).
    public func cachedRecent() -> [AuditLogEntry] {
        let cutoff = Date().addingTimeInterval(-cacheTTL)
        return cache.filter { $0.createdAt >= cutoff }
                    .sorted { $0.createdAt > $1.createdAt }
    }

    /// §50.10 — Evict entries older than cacheTTL and cap at cacheCapacity.
    private func mergeIntoCache(_ entries: [AuditLogEntry]) {
        let cutoff = Date().addingTimeInterval(-cacheTTL)
        // Add new entries that are not already cached (by id).
        let existingIds = Set(cache.map { $0.id })
        let fresh = entries.filter { !existingIds.contains($0.id) && $0.createdAt >= cutoff }
        cache.append(contentsOf: fresh)
        // Drop old entries and enforce capacity cap (newest retained).
        cache = cache
            .filter { $0.createdAt >= cutoff }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(cacheCapacity)
            .map { $0 }
        cacheLastUpdated = Date()
    }
}
