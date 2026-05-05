package com.bizarreelectronics.crm.data.local.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.bizarreelectronics.crm.data.local.db.entities.SyncStateEntity
import kotlinx.coroutines.flow.Flow

/**
 * DAO for [SyncStateEntity].
 *
 * ## Null-to-sentinel convention
 *
 * Room composite PKs cannot contain nullable columns. Pass `""` for no
 * filter and `0L` for no parent when querying root-level collections.
 * The [get] and [observe] helpers accept nullable arguments and coerce
 * them to the sentinel values automatically.
 *
 * ## hasMore
 *
 * [hasMore] returns `true` when [SyncStateEntity.serverExhaustedAt] is null,
 * meaning the server has not yet confirmed all pages have been fetched.
 */
@Dao
interface SyncStateDao {

    /**
     * Insert or replace a [SyncStateEntity].
     *
     * Callers should build an updated copy of the existing entity (immutable
     * pattern) and pass it here — Room's REPLACE strategy handles both insert
     * and update in one operation.
     */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: SyncStateEntity)

    /**
     * Fetch the sync state for a collection, or null if not yet recorded.
     *
     * @param entity  logical collection name, e.g. `"tickets"`.
     * @param filter  optional filter tag; pass `null` for no filter.
     * @param parentId optional parent entity ID; pass `null` for root collections.
     */
    @Query(
        """
        SELECT * FROM sync_state
        WHERE entity = :entity
          AND filter_key = :filter
          AND parent_id  = :parentId
        LIMIT 1
        """
    )
    suspend fun get(
        entity: String,
        filter: String = "",
        parentId: Long = 0L,
    ): SyncStateEntity?

    /**
     * Observe the sync state for a collection as a [Flow].
     *
     * Emits a new value whenever the row is inserted, updated, or deleted.
     * Emits `null` when no row exists yet for the given key.
     */
    @Query(
        """
        SELECT * FROM sync_state
        WHERE entity = :entity
          AND filter_key = :filter
          AND parent_id  = :parentId
        LIMIT 1
        """
    )
    fun observe(
        entity: String,
        filter: String = "",
        parentId: Long = 0L,
    ): Flow<SyncStateEntity?>

    /**
     * Returns `true` when [SyncStateEntity.serverExhaustedAt] is null for the
     * given key, meaning more pages may still be available from the server.
     *
     * Also returns `true` if no row exists yet (conservative: assume more data).
     */
    @Query(
        """
        SELECT CASE
            WHEN COUNT(*) = 0          THEN 1
            WHEN server_exhausted_at IS NULL THEN 1
            ELSE 0
        END
        FROM sync_state
        WHERE entity = :entity
          AND filter_key = :filter
          AND parent_id  = :parentId
        """
    )
    suspend fun hasMore(
        entity: String,
        filter: String = "",
        parentId: Long = 0L,
    ): Boolean

    /**
     * Delete all sync-state rows. Called on logout to clear cached pagination
     * state so the next user starts fresh.
     */
    @Query("DELETE FROM sync_state")
    suspend fun clear()
}
