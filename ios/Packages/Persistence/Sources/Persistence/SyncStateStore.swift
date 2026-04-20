import Foundation
import GRDB
import Core

/// Cursor-pagination bookkeeping per §20.5.
/// One row per (entity, filter, parent). Drives every list's `hasMore`
/// decision locally — the plan explicitly bans reading `total_pages`
/// from the server.
public struct SyncStateRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "sync_state"

    public var entity: String
    public var filterKey: String
    public var parentId: String
    public var cursor: String?
    public var oldestCachedAt: Date?
    public var serverExhaustedAt: Date?
    public var lastUpdatedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case entity
        case filterKey = "filter_key"
        case parentId = "parent_id"
        case cursor
        case oldestCachedAt = "oldest_cached_at"
        case serverExhaustedAt = "server_exhausted_at"
        case lastUpdatedAt = "last_updated_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        entity: String,
        filterKey: String = "",
        parentId: String = "",
        cursor: String? = nil,
        oldestCachedAt: Date? = nil,
        serverExhaustedAt: Date? = nil,
        lastUpdatedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.entity = entity
        self.filterKey = filterKey
        self.parentId = parentId
        self.cursor = cursor
        self.oldestCachedAt = oldestCachedAt
        self.serverExhaustedAt = serverExhaustedAt
        self.lastUpdatedAt = lastUpdatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public actor SyncStateStore {
    public static let shared = SyncStateStore()
    private init() {}

    /// Look up cursor state. Returns nil if never seen this entity+filter+parent.
    public func state(
        entity: String,
        filterKey: String = "",
        parentId: String = ""
    ) async throws -> SyncStateRecord? {
        guard let pool = await Database.shared.pool() else { return nil }
        return try await pool.read { db in
            try SyncStateRecord
                .filter(
                    Column("entity") == entity
                        && Column("filter_key") == filterKey
                        && Column("parent_id") == parentId
                )
                .fetchOne(db)
        }
    }

    /// Upsert cursor bookkeeping after a page fetch.
    /// If `serverExhaustedAt` supplied, list is known-complete and
    /// `loadMoreIfNeeded` becomes a no-op even online.
    public func upsert(
        entity: String,
        filterKey: String = "",
        parentId: String = "",
        cursor: String? = nil,
        oldestCachedAt: Date? = nil,
        serverExhaustedAt: Date? = nil,
        lastUpdatedAt: Date? = nil
    ) async throws {
        guard let pool = await Database.shared.pool() else { return }
        let now = Date()
        try await pool.write { db in
            var existing = try SyncStateRecord
                .filter(
                    Column("entity") == entity
                        && Column("filter_key") == filterKey
                        && Column("parent_id") == parentId
                )
                .fetchOne(db)
            if existing == nil {
                existing = SyncStateRecord(
                    entity: entity,
                    filterKey: filterKey,
                    parentId: parentId,
                    cursor: cursor,
                    oldestCachedAt: oldestCachedAt,
                    serverExhaustedAt: serverExhaustedAt,
                    lastUpdatedAt: lastUpdatedAt,
                    createdAt: now,
                    updatedAt: now
                )
            } else {
                if let cursor { existing?.cursor = cursor }
                if let oldestCachedAt { existing?.oldestCachedAt = oldestCachedAt }
                if let serverExhaustedAt { existing?.serverExhaustedAt = serverExhaustedAt }
                if let lastUpdatedAt { existing?.lastUpdatedAt = lastUpdatedAt }
                existing?.updatedAt = now
            }
            try existing?.save(db)
        }
    }

    /// Clear the cursor state on schema migration / user-initiated full resync.
    public func reset(entity: String) async throws {
        guard let pool = await Database.shared.pool() else { return }
        _ = try await pool.write { db in
            try SyncStateRecord
                .filter(Column("entity") == entity)
                .deleteAll(db)
        }
    }

    /// `hasMore` decision driven purely by local state — never consults the server.
    public func hasMore(
        entity: String,
        filterKey: String = "",
        parentId: String = ""
    ) async throws -> Bool {
        let s = try await state(entity: entity, filterKey: filterKey, parentId: parentId)
        guard let s else { return true }          // never fetched → always more
        if s.serverExhaustedAt != nil { return false }
        return true
    }
}
