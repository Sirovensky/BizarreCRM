import Foundation
import Core

// MARK: - ReadStrategy (§20.1)

/// Controls how a `CachedRepository` satisfies a read request.
///
/// - `networkOnly`: Skip local cache; fetch fresh from server. Fails offline.
/// - `cacheOnly`: Return local GRDB data only; never attempt a network call.
///   Use for guaranteed-offline screens.
/// - `cacheFirst`: Return local data immediately; if stale, refresh in the
///   background (default). Best for most interactive lists.
/// - `cacheThenNetwork`: Return local data immediately AND fire a remote
///   refresh unconditionally; UI re-renders when refresh completes
///   (stale-while-revalidate pattern).
public enum ReadStrategy: String, Sendable, CaseIterable {
    case networkOnly
    case cacheOnly
    case cacheFirst
    case cacheThenNetwork
}

// MARK: - CacheSource

/// Where the data in a `CachedResult` came from.
public enum CacheSource: String, Sendable {
    case cache    // Served entirely from local GRDB store.
    case remote   // Fetched fresh from the server.
    case merged   // Local data supplemented with a remote refresh.
}

// MARK: - CachedResult

/// Container returned from every `CachedRepository.list(…)` call.
public struct CachedResult<T: Sendable>: Sendable {
    /// The data payload.
    public let value: T
    /// Where the data came from.
    public let source: CacheSource
    /// When the cache was last populated from the server.
    public let lastSyncedAt: Date?
    /// `true` when the cache age exceeds the requested `maxAgeSeconds`.
    public let isStale: Bool

    public init(
        value: T,
        source: CacheSource,
        lastSyncedAt: Date?,
        isStale: Bool
    ) {
        self.value = value
        self.source = source
        self.lastSyncedAt = lastSyncedAt
        self.isStale = isStale
    }
}

// MARK: - CachedRepository

/// Write-through cache contract for every domain repository.
///
/// Domain packages conform their `XyzRepository` to this protocol.
/// The Sync package never imports domain packages — only this protocol lives here.
///
/// ### Read contract
/// `list(filter:maxAgeSeconds:)` must:
/// 1. Return local cache immediately.
/// 2. If `isStale`, trigger a remote refresh in the background (best-effort).
/// 3. The background refresh should upsert results into GRDB; SwiftUI
///    `ValueObservation` re-renders automatically.
///
/// ### Write contract
/// `create`, `update`, `delete` must:
/// 1. Apply the change optimistically to the local GRDB store.
/// 2. Enqueue a `SyncOp` via `SyncManager.shared.enqueue(_:)`.
/// 3. Return immediately — the drain loop handles the remote call.
public protocol CachedRepository: Sendable {
    associatedtype Entity: Sendable
    associatedtype ListFilter: Sendable

    /// Read from local cache immediately; if stale, trigger remote refresh.
    func list(filter: ListFilter, maxAgeSeconds: Int) async throws -> CachedResult<[Entity]>

    /// Persist locally + enqueue sync op. Returns the locally-saved entity
    /// (may carry a negative sentinel ID until the server round-trip completes).
    func create(_ entity: Entity) async throws -> Entity

    /// Persist locally + enqueue sync op. Returns the updated entity.
    func update(_ entity: Entity) async throws -> Entity

    /// Delete locally + enqueue sync op.
    func delete(id: String) async throws
}

// MARK: - AbstractCachedRepository

/// Generic helper that domain repositories subclass (or compose) to satisfy
/// `CachedRepository`. Wires together:
/// - A local DAO (GRDB) for reads and optimistic writes.
/// - A remote fetcher closure for pulling fresh data.
/// - A `SyncOp` builder closure for enqueuing writes.
///
/// All three are injected at construction so the Sync package stays domain-free.
///
/// ### Usage
/// ```swift
/// // In TicketsRepository:
/// let base = AbstractCachedRepository(
///     entityName: "tickets",
///     localFetch: { filter in try dao.fetchAll(filter: filter) },
///     remoteFetch: { filter in try await APIClient.shared.getTickets(filter: filter) },
///     localUpsert: { entities in try dao.upsertAll(entities) },
///     localDelete: { id in try dao.delete(id: id) },
///     syncOpBuilder: { entity, op in SyncOp(op: op, entity: "tickets", payload: ...) }
/// )
/// ```
public actor AbstractCachedRepository<Entity: Sendable, ListFilter: Sendable> {

    // MARK: - Injected dependencies (all sendable closures)

    private let entityName: String
    private let localFetch: @Sendable (ListFilter) async throws -> [Entity]
    private let remoteFetch: @Sendable (ListFilter) async throws -> [Entity]
    private let localUpsert: @Sendable ([Entity]) async throws -> Void
    private let localDelete: @Sendable (String) async throws -> Void
    private let syncOpBuilder: @Sendable (Entity, String) async throws -> SyncOp
    private let idExtractor: @Sendable (Entity) -> String
    private let lastSyncedAt: @Sendable (String) async -> Date?

    // MARK: - Init

    public init(
        entityName: String,
        localFetch: @escaping @Sendable (ListFilter) async throws -> [Entity],
        remoteFetch: @escaping @Sendable (ListFilter) async throws -> [Entity],
        localUpsert: @escaping @Sendable ([Entity]) async throws -> Void,
        localDelete: @escaping @Sendable (String) async throws -> Void,
        syncOpBuilder: @escaping @Sendable (Entity, String) async throws -> SyncOp,
        idExtractor: @escaping @Sendable (Entity) -> String,
        lastSyncedAt: @escaping @Sendable (String) async -> Date?
    ) {
        self.entityName = entityName
        self.localFetch = localFetch
        self.remoteFetch = remoteFetch
        self.localUpsert = localUpsert
        self.localDelete = localDelete
        self.syncOpBuilder = syncOpBuilder
        self.idExtractor = idExtractor
        self.lastSyncedAt = lastSyncedAt
    }

    // MARK: - CachedRepository implementation

    public func list(filter: ListFilter, maxAgeSeconds: Int) async throws -> CachedResult<[Entity]> {
        // 1. Read local cache immediately.
        let cached = try await localFetch(filter)
        let syncedAt = await lastSyncedAt(entityName)

        let isStale: Bool
        if let syncedAt {
            isStale = Date().timeIntervalSince(syncedAt) > Double(maxAgeSeconds)
        } else {
            isStale = true  // Never fetched → always stale.
        }

        // 2. If stale, kick a background remote fetch (fire-and-forget).
        if isStale {
            let entityName = self.entityName
            let upsert = self.localUpsert
            let fetch = self.remoteFetch
            Task {
                do {
                    let fresh = try await fetch(filter)
                    try await upsert(fresh)
                    AppLog.sync.debug("\(entityName, privacy: .public) remote refresh: \(fresh.count, privacy: .public) rows")
                } catch {
                    // Best-effort — UI is already showing cache.
                    AppLog.sync.warning("\(entityName, privacy: .public) remote refresh failed: \(error, privacy: .public)")
                }
            }
        }

        return CachedResult(
            value: cached,
            source: isStale ? .cache : .cache,  // Starts as cache; merged after background refresh.
            lastSyncedAt: syncedAt,
            isStale: isStale
        )
    }

    public func create(_ entity: Entity) async throws -> Entity {
        // 1. Persist locally (optimistic).
        try await localUpsert([entity])
        // 2. Enqueue sync op.
        let op = try await syncOpBuilder(entity, "create")
        await SyncManager.shared.enqueue(op)
        AppLog.sync.debug("\(self.entityName, privacy: .public) create enqueued")
        return entity
    }

    public func update(_ entity: Entity) async throws -> Entity {
        // 1. Persist locally (optimistic).
        try await localUpsert([entity])
        // 2. Enqueue sync op.
        let op = try await syncOpBuilder(entity, "update")
        await SyncManager.shared.enqueue(op)
        AppLog.sync.debug("\(self.entityName, privacy: .public) update enqueued")
        return entity
    }

    public func delete(id: String) async throws {
        // 1. Delete locally (optimistic).
        try await localDelete(id)
        // 2. Enqueue sync op with a minimal sentinel entity.
        // We build a tombstone payload directly since we can't reconstruct the entity.
        let payloadData = try JSONEncoder().encode(["id": id, "deleted": "true"])
        let tombstoneOp = SyncOp(
            op: "delete",
            entity: entityName,
            entityLocalId: id,
            payload: payloadData
        )
        await SyncManager.shared.enqueue(tombstoneOp)
        AppLog.sync.debug("\(self.entityName, privacy: .public) delete enqueued for id=\(id, privacy: .private)")
    }
}

// MARK: - CachedRepository conformance via AbstractCachedRepository

extension AbstractCachedRepository: CachedRepository {}
