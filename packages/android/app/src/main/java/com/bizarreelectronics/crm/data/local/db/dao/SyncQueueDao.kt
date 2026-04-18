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
     */
    @Query("UPDATE sync_queue SET status = 'pending', retries = 0, last_error = NULL WHERE id = :id")
    suspend fun resurrectDeadLetter(id: Long)

    companion object {
        /** Max attempts before an entry is moved to the dead-letter queue. */
        const val MAX_RETRIES = 5

        /** Days to retain dead-letter entries before purging. */
        const val DEAD_LETTER_RETENTION_DAYS = 30
    }
}
