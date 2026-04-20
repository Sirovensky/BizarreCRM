import Foundation
import GRDB
import Core

/// Optimistic-write log. §20.2.
///
/// Every mutation enqueues a row here with an idempotency key; drain loop
/// retries with exp backoff; hard fail → `sync_dead_letter` row.
public struct SyncQueueRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "sync_queue"

    public enum Status: String, Codable, Sendable {
        case queued     // waiting for next drain
        case inFlight   // drain loop picked it up
        case failed     // transient failure, will retry
        case deadLetter // moved to sync_dead_letter; this row is archived but left
    }

    public var id: Int64?
    public var op: String?              // "create", "update", "patch", "delete", "upload_photo", "charge"
    public var entity: String?
    public var entityLocalId: String?
    public var entityServerId: String?
    public var payload: String          // JSON; historical NOT NULL
    public var idempotencyKey: String?
    public var status: String = Status.queued.rawValue
    public var attemptCount: Int = 0
    public var lastAttempt: Date?
    public var lastError: String?
    public var nextRetryAt: Date?
    public var enqueuedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case op
        case entity
        case entityLocalId = "entity_local_id"
        case entityServerId = "entity_server_id"
        case payload
        case idempotencyKey = "idempotency_key"
        case status
        case attemptCount = "attempt_count"
        case lastAttempt = "last_attempt"
        case lastError = "last_error"
        case nextRetryAt = "next_retry_at"
        case enqueuedAt = "enqueued_at"
        case kind   // legacy — first migration used `kind`; still present, we leave it unset
    }

    public var kind: String?

    public init(
        op: String,
        entity: String,
        entityLocalId: String? = nil,
        entityServerId: String? = nil,
        payload: String,
        idempotencyKey: String = UUID().uuidString,
        enqueuedAt: Date = Date()
    ) {
        self.op = op
        self.entity = entity
        self.entityLocalId = entityLocalId
        self.entityServerId = entityServerId
        self.payload = payload
        self.idempotencyKey = idempotencyKey
        self.enqueuedAt = enqueuedAt
        self.kind = "\(entity).\(op)"
    }

    public mutating func didEncounter(error: String, backoffSeconds: TimeInterval) {
        self.attemptCount += 1
        self.lastAttempt = Date()
        self.lastError = error
        self.status = Status.failed.rawValue
        self.nextRetryAt = Date().addingTimeInterval(backoffSeconds)
    }
}

public actor SyncQueueStore {
    public static let shared = SyncQueueStore()
    private init() {}

    /// Max retries before moving to dead-letter (§20.2).
    public static let maxAttempts = 10

    public func enqueue(_ record: SyncQueueRecord) async throws {
        guard let pool = await Database.shared.pool() else { return }
        try await pool.write { db in
            // INSERT OR IGNORE on idempotency key — same payload queued twice
            // (common with UI retries) silently dedupes.
            if let key = record.idempotencyKey {
                let existing = try SyncQueueRecord
                    .filter(Column("idempotency_key") == key)
                    .fetchOne(db)
                if existing != nil {
                    AppLog.sync.debug("sync_queue dedupe on idempotency key")
                    return
                }
            }
            var row = record
            try row.insert(db)
        }
    }

    /// Rows ready to attempt now (queued OR failed past next_retry_at).
    public func due(limit: Int = 50) async throws -> [SyncQueueRecord] {
        guard let pool = await Database.shared.pool() else { return [] }
        return try await pool.read { db in
            try SyncQueueRecord
                .filter(Column("status") == SyncQueueRecord.Status.queued.rawValue
                        || (Column("status") == SyncQueueRecord.Status.failed.rawValue
                            && (Column("next_retry_at") == nil
                                || Column("next_retry_at") <= Date())))
                .order(Column("enqueued_at"))
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func markInFlight(_ id: Int64) async throws {
        guard let pool = await Database.shared.pool() else { return }
        try await pool.write { db in
            guard var row = try SyncQueueRecord.filter(Column("id") == id).fetchOne(db) else { return }
            row.status = SyncQueueRecord.Status.inFlight.rawValue
            try row.update(db)
        }
    }

    public func markSucceeded(_ id: Int64) async throws {
        guard let pool = await Database.shared.pool() else { return }
        _ = try await pool.write { db in
            try SyncQueueRecord.filter(Column("id") == id).deleteAll(db)
        }
    }

    public func markFailed(_ id: Int64, error: String) async throws {
        guard let pool = await Database.shared.pool() else { return }
        try await pool.write { db in
            guard var row = try SyncQueueRecord.filter(Column("id") == id).fetchOne(db) else { return }
            row.attemptCount += 1
            row.lastAttempt = Date()
            row.lastError = error

            if row.attemptCount >= SyncQueueStore.maxAttempts {
                // §20.2 — move to dead-letter, delete from queue.
                try db.execute(sql: """
                    INSERT INTO sync_dead_letter
                        (op, entity, payload, idempotency_key, attempt_count,
                         last_error, first_attempted, last_attempted, moved_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        row.op ?? "unknown",
                        row.entity ?? "unknown",
                        row.payload,
                        row.idempotencyKey,
                        row.attemptCount,
                        row.lastError,
                        row.enqueuedAt,
                        row.lastAttempt ?? Date(),
                        Date()
                    ]
                )
                try SyncQueueRecord.filter(Column("id") == id).deleteAll(db)
                AppLog.sync.error("sync_queue → dead_letter after \(row.attemptCount) attempts")
            } else {
                let backoff = Self.backoff(attempt: row.attemptCount)
                row.nextRetryAt = Date().addingTimeInterval(backoff)
                row.status = SyncQueueRecord.Status.failed.rawValue
                try row.update(db)
            }
        }
    }

    public func pendingCount() async throws -> Int {
        guard let pool = await Database.shared.pool() else { return 0 }
        return try await pool.read { db in
            try SyncQueueRecord.fetchCount(db)
        }
    }

    // ── Exponential backoff with ±10% jitter per §20.2. 1s → 2s → 4s → 8s →
    // 16s → 32s → 60s cap.
    static func backoff(attempt: Int) -> TimeInterval {
        let base = min(pow(2.0, Double(attempt - 1)), 60.0)
        let jitter = Double.random(in: 0.9...1.1)
        return base * jitter
    }

}
