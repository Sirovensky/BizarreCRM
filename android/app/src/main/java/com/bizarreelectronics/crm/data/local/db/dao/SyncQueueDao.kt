package com.bizarreelectronics.crm.data.local.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity
import kotlinx.coroutines.flow.Flow

/**
 * Sync queue persistence.
 *
 * Entry status lifecycle:
 *  - `pending`     Newly-queued or awaiting next flush cycle.
 *  - `syncing`     Currently being dispatched.
 *  - `completed`   Successfully flushed. Swept by [deleteCompleted].
 *  - `dead_letter` Exceeded [MAX_RETRIES] — kept for diagnostics/manual retry. Held
 *                  for [DEAD_LETTER_RETENTION_DAYS] before being purged by
 *                  [purgeOldDeadLetters]. See R9 / N8.
 *
 * AUD-20260414-M5: surfaced in the "Sync Issues" screen under Settings/More —
 * [observeDeadLetterEntries] drives the LazyColumn, [countDeadLetter] drives
 * the tile badge, and the per-row Retry button calls
 * [com.bizarreelectronics.crm.data.sync.SyncManager.retryDeadLetter] which in
 * turn delegates to [resurrectDeadLetter].
 */
@Dao
interface SyncQueueDao {

    @Query("SELECT * FROM sync_queue WHERE status = 'pending' ORDER BY created_at ASC")
    suspend fun getPending(): List<SyncQueueEntity>

    @Query("SELECT * FROM sync_queue WHERE status = :status ORDER BY created_at ASC")
    suspend fun getByStatus(status: String): List<SyncQueueEntity>

    /**
     * Look up an existing queue entry for a specific entity + operation. Used by
     * SyncManager's conflict-reconciliation path to detect whether a prior attempt at
     * the same logical change already succeeded on the server under a different id.
     */
    @Query(
        """
        SELECT * FROM sync_queue
        WHERE entity_type = :entityType AND entity_id = :entityId AND operation = :operation
        ORDER BY created_at DESC
        LIMIT 1
        """
    )
    suspend fun findByEntity(entityType: String, entityId: Long, operation: String): SyncQueueEntity?

    /**
     * Sync queue rows are append-only — the primary key is auto-generated so there
     * is never a conflict. ABORT is the correct strategy because an ID collision
     * would indicate a bug in the queue, not a duplicate payload to ignore.
     */
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(entry: SyncQueueEntity): Long

    @Query("UPDATE sync_queue SET status = :status, last_error = :error WHERE id = :id")
    suspend fun updateStatus(id: Long, status: String, error: String?)

    @Query("UPDATE sync_queue SET payload = :payload WHERE id = :id")
    suspend fun updatePayload(id: Long, payload: String)

    /**
     * Return every pending queue entry whose JSON payload embeds the given
     * customer id as a `"customer_id":<id>` pair. Used by SyncManager's
     * customer reconciliation path (AND-20260414-H5) so that newly-created
     * tickets/estimates queued against a temp customer id can have their
     * payloads rewritten to the real server id before they are POSTed.
     *
     * Matches the Gson serialization produced by CreateTicketRequest,
     * UpdateTicketRequest, CreateEstimateRequest, UpdateEstimateRequest, etc.
     * where the column name in the request body is the snake_case
     * `customer_id`. Uses GLOB so negative ids (leading `-`) match without
     * special escaping. Limited to `status = 'pending'` so rows currently
     * being dispatched are not mutated under the flush loop.
     */
    @Query(
        """
        SELECT * FROM sync_queue
        WHERE status = 'pending'
          AND payload GLOB '*"customer_id":' || :tempId || '*'
        """
    )
    suspend fun findPendingEntriesReferencingCustomerId(tempId: Long): List<SyncQueueEntity>

    @Query("UPDATE sync_queue SET retries = retries + 1 WHERE id = :id")
    suspend fun incrementRetry(id: Long)

    @Query("DELETE FROM sync_queue WHERE status = 'completed'")
    suspend fun deleteCompleted()

    @Query("SELECT COUNT(*) FROM sync_queue WHERE status = 'pending'")
    fun getCount(): Flow<Int>

    /**
     * Count pending entries whose [SyncQueueEntity.operation] matches [opType].
     * Used by PosCartViewModel to surface the "N sale(s) queued" offline-banner count.
     */
    @Query("SELECT COUNT(*) FROM sync_queue WHERE status = 'pending' AND operation = :opType")
    suspend fun countPendingByOpType(opType: String): Int

    // ─── Dead-letter queue (R9 / N8) ─────────────────────────────────────────────

    /**
     * Entries that exhausted [MAX_RETRIES] attempts without success. They stay in
     * the table (not deleted) so the user can inspect, retry, or discard them via
     * a future diagnostic screen.
     */
    @Query("SELECT * FROM sync_queue WHERE status = 'dead_letter' ORDER BY created_at DESC")
    suspend fun getDeadLetterEntries(): List<SyncQueueEntity>

    /** Reactive variant of [getDeadLetterEntries] for UI dashboards. */
    @Query("SELECT * FROM sync_queue WHERE status = 'dead_letter' ORDER BY created_at DESC")
    fun observeDeadLetterEntries(): Flow<List<SyncQueueEntity>>

    @Query("SELECT COUNT(*) FROM sync_queue WHERE status = 'dead_letter'")
    fun getDeadLetterCount(): Flow<Int>

    /**
     * §20.7 — Reactive count of dead-letter entries for a specific entity type.
     * Used by per-screen "N [entity] failed to sync" persistent banners. The entity
     * type must match the snake_case values stored by SyncManager (e.g. `"ticket"`,
     * `"customer"`, `"inventory"`).
     */
    @Query("SELECT COUNT(*) FROM sync_queue WHERE status = 'dead_letter' AND entity_type = :entityType")
    fun getDeadLetterCountForEntity(entityType: String): Flow<Int>

    /**
     * AUD-20260414-M5: one-shot suspend variant used by the "Sync Issues" tile
     * badge on the Settings/More screen. The tile is a synchronous entry — it
     * does not need the Flow reactive contract that [getDeadLetterCount] offers.
     */
    @Query("SELECT COUNT(*) FROM sync_queue WHERE status = 'dead_letter'")
    suspend fun countDeadLetter(): Int

    /**
     * Mark an entry as dead-lettered. Preserves `retries`, `payload`, and the latest
     * error so the user can troubleshoot or manually retry.
     */
    @Query("UPDATE sync_queue SET status = 'dead_letter', last_error = :error WHERE id = :id")
    suspend fun markDeadLetter(id: Long, error: String?)

    /**
     * Purge dead-letter entries older than [olderThanMillis] (epoch ms). Callers pass
     * `System.currentTimeMillis() - DEAD_LETTER_RETENTION_DAYS.days.inWholeMilliseconds`
     * to enforce the 30-day retention policy described in the audit.
     */
    @Query("DELETE FROM sync_queue WHERE status = 'dead_letter' AND created_at < :olderThanMillis")
    suspend fun purgeOldDeadLetters(olderThanMillis: Long)

    /**
     * Reset a dead-letter entry back to `pending` so the next flush will retry it.
     * Retry counter is zeroed so the entry gets a fresh budget.
     *
     * §20.7 — [newIdempotencyKey] rotates the idempotency key so the server does NOT
     * treat the retried request as a duplicate of the original failed attempt. Without
     * a fresh key, a server that already processed the request and returned an error
     * could still respond with 409 Conflict on the retry, permanently blocking the
     * row. Callers must supply a UUID generated via [OfflineIdGenerator.newIdempotencyKey].
     */
    @Query(
        "UPDATE sync_queue SET status = 'pending', retries = 0, last_error = NULL, " +
            "idempotency_key = :newIdempotencyKey WHERE id = :id",
    )
    suspend fun resurrectDeadLetter(id: Long, newIdempotencyKey: String)

    /**
     * §20.7 — Same as [resurrectDeadLetter] but also rotates the idempotency key.
     * Rotating the key is important when the server may have partially-applied the
     * previous attempt: a stale key would cause the server to deduplicate the retry
     * as if it had succeeded, silently dropping the user's change.
     *
     * Callers must generate a fresh UUID and pass it as [freshKey].
     */
    @Query("UPDATE sync_queue SET status = 'pending', retries = 0, last_error = NULL, idempotency_key = :freshKey WHERE id = :id")
    suspend fun resurrectDeadLetterWithFreshKey(id: Long, freshKey: String)

    // ─── Ordered queue (plan §20.4 L2112) ────────────────────────────────────────

    /**
     * Returns the single oldest `pending` entry whose dependency is satisfied:
     *
     *  - `depends_on_queue_id IS NULL` — no dependency, always eligible.
     *  - `depends_on_queue_id` refers to a row whose `status = 'completed'` — dependency
     *    fulfilled.
     *
     * Entries whose parent is still `pending` / `syncing` / `dead_letter` are skipped
     * so that the dependency ordering is preserved. Called by [OrderedQueueProcessor]
     * on every drain tick.
     *
     * The LEFT JOIN approach is O(log n) when the (status, created_at) composite index
     * is used for the outer WHERE and the depends_on_queue_id index covers the join.
     */
    @Query(
        """
        SELECT q.*
        FROM sync_queue q
        LEFT JOIN sync_queue parent ON q.depends_on_queue_id = parent.id
        WHERE q.status = 'pending'
          AND (q.depends_on_queue_id IS NULL OR parent.status = 'completed')
        ORDER BY q.created_at ASC
        LIMIT 1
        """
    )
    suspend fun nextReady(): SyncQueueEntity?

    /**
     * Mark a batch of entries as `syncing` atomically. Called by [OrderedQueueProcessor]
     * when it claims a window of ready entries for dispatch.
     */
    @Query("UPDATE sync_queue SET status = 'syncing' WHERE id IN (:ids)")
    suspend fun markSyncing(ids: List<Long>)

    companion object {
        /** Max attempts before an entry is moved to the dead-letter queue. */
        const val MAX_RETRIES = 5

        /** Days to retain dead-letter entries before purging. */
        const val DEAD_LETTER_RETENTION_DAYS = 30
    }
}
