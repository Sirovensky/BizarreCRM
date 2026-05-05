import Foundation
import GRDB
import Persistence
import Core

// MARK: - DeadLetterItem

/// View-layer model wrapping a `SyncQueueStore.DeadLetterRow` with
/// the full payload string for the detail screen.
public struct DeadLetterItem: Identifiable, Sendable {
    public let id: Int64
    public let op: String
    public let entity: String
    public let attemptCount: Int
    public let lastError: String?
    public let movedAt: Date
    /// Raw JSON payload as stored in sync_queue / sync_dead_letter.
    public let payload: String

    public init(
        id: Int64,
        op: String,
        entity: String,
        attemptCount: Int,
        lastError: String?,
        movedAt: Date,
        payload: String
    ) {
        self.id = id
        self.op = op
        self.entity = entity
        self.attemptCount = attemptCount
        self.lastError = lastError
        self.movedAt = movedAt
        self.payload = payload
    }
}

// MARK: - DeadLetterRepository

/// Wraps `SyncQueueStore` queries for `status='deadLetter'` rows.
/// Domain-free: no imports of feature packages.
public actor DeadLetterRepository {
    public static let shared = DeadLetterRepository()
    private init() {}

    private let store = SyncQueueStore.shared

    /// Returns all dead-letter rows (up to `limit`), newest first.
    public func fetchAll(limit: Int = 50) async throws -> [DeadLetterItem] {
        let rows = try await store.deadLetter(limit: limit)
        // Fetch payloads in one shot by joining; SyncQueueStore.deadLetter
        // already has all the fields we need except payload — fetch via pool.
        // For now we use the available API and set payload to "".
        // Real payload stored in sync_dead_letter.payload column.
        return rows.map { row in
            DeadLetterItem(
                id: row.id,
                op: row.op,
                entity: row.entity,
                attemptCount: row.attemptCount,
                lastError: row.lastError,
                movedAt: row.movedAt,
                payload: ""  // populated by fetchDetail(_:)
            )
        }
    }

    /// Fetch a single dead-letter item including payload, for the detail screen.
    public func fetchDetail(_ id: Int64) async throws -> DeadLetterItem? {
        guard let pool = await Database.shared.pool() else { return nil }
        return try await pool.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT id, op, entity, attempt_count, last_error, moved_at, payload
                FROM sync_dead_letter WHERE id = ?
                """, arguments: [id])
            guard let row else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallback = ISO8601DateFormatter()
            let movedRaw: String = row["moved_at"] ?? ""
            let moved = formatter.date(from: movedRaw) ?? fallback.date(from: movedRaw) ?? Date()
            return DeadLetterItem(
                id: row["id"] ?? id,
                op: row["op"] ?? "",
                entity: row["entity"] ?? "",
                attemptCount: row["attempt_count"] ?? 0,
                lastError: row["last_error"],
                movedAt: moved,
                payload: row["payload"] ?? ""
            )
        }
    }

    /// Re-queue a dead-letter row as fresh (attempts=0, status=queued).
    public func retry(_ id: Int64) async throws {
        try await store.retryDeadLetter(id)
        AppLog.sync.info("Dead-letter \(id, privacy: .public) re-queued for retry")
    }

    /// Permanently discard a dead-letter row.
    public func discard(_ id: Int64) async throws {
        try await store.discardDeadLetter(id)
        AppLog.sync.info("Dead-letter \(id, privacy: .public) discarded")
    }

    /// Total count for badge display.
    public func count() async throws -> Int {
        try await store.deadLetterCount()
    }
}
