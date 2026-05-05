package com.bizarreelectronics.crm.data.local.draft

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

/**
 * Room DAO for [DraftEntity].
 *
 * The unique index on `(user_id, draft_type)` combined with
 * [OnConflictStrategy.REPLACE] in [upsert] ensures that saving a draft twice
 * for the same type silently replaces the prior row — no duplicates can
 * accumulate.  (Plan line 263)
 */
@Dao
interface DraftDao {

    /**
     * Returns the single draft for [userId] + [type], or `null` if none exists.
     * The `LIMIT 1` is defensive; the unique index guarantees at most one row.
     */
    @Query(
        "SELECT * FROM drafts WHERE user_id = :userId AND draft_type = :type LIMIT 1"
    )
    suspend fun getForType(userId: String, type: String): DraftEntity?

    /**
     * Insert or replace (upsert).  Because the unique index covers
     * `(user_id, draft_type)`, a duplicate row triggers REPLACE which
     * atomically deletes the old row and inserts the new one, preserving
     * the "one draft per type" invariant without a manual delete first.
     */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(draft: DraftEntity)

    /**
     * Permanently removes the draft for [userId] + [type].  Called when the
     * user explicitly discards a draft or successfully submits the form.
     */
    @Query("DELETE FROM drafts WHERE user_id = :userId AND draft_type = :type")
    suspend fun deleteForType(userId: String, type: String)

    /**
     * Prunes rows older than [olderThanMs] (epoch millis).  Returns the number
     * of rows deleted.  Called by [DraftStore.pruneOlderThanDays] on app startup
     * to enforce the 30-day retention policy (plan line 266).
     */
    @Query("DELETE FROM drafts WHERE saved_at < :olderThanMs")
    suspend fun deleteOlderThan(olderThanMs: Long): Int

    /**
     * Live observable stream of all drafts for [userId], ordered newest-first.
     * Consumed by the recovery-prompt composable (plan line 261) — which is
     * implemented in a later wave — and available as a debugging aid.
     */
    @Query(
        "SELECT * FROM drafts WHERE user_id = :userId ORDER BY saved_at DESC"
    )
    fun observeAllForUser(userId: String): Flow<List<DraftEntity>>
}
