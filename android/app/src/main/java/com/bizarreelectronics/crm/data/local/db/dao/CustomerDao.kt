package com.bizarreelectronics.crm.data.local.db.dao

import androidx.paging.PagingSource
import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import androidx.room.Upsert
import com.bizarreelectronics.crm.data.local.db.entities.CustomerEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface CustomerDao {

    // -----------------------------------------------------------------------
    // Paging3 PagingSources (plan:L874)
    // -----------------------------------------------------------------------

    /** Default paging source: most-recently-updated first. */
    @Query("SELECT * FROM customers WHERE is_deleted = 0 ORDER BY updated_at DESC")
    fun pagingSource(): PagingSource<Int, CustomerEntity>

    /** A–Z by first + last name. */
    @Query("SELECT * FROM customers WHERE is_deleted = 0 ORDER BY first_name ASC, last_name ASC")
    fun pagingSourceAZ(): PagingSource<Int, CustomerEntity>

    /** Z–A by first + last name. */
    @Query("SELECT * FROM customers WHERE is_deleted = 0 ORDER BY first_name DESC, last_name DESC")
    fun pagingSourceZA(): PagingSource<Int, CustomerEntity>

    @Query("SELECT * FROM customers WHERE is_deleted = 0 ORDER BY first_name ASC, last_name ASC")
    fun getAll(): Flow<List<CustomerEntity>>

    @Query("SELECT * FROM customers WHERE id = :id")
    fun getById(id: Long): Flow<CustomerEntity?>

    @Query(
        """
        SELECT * FROM customers
        WHERE is_deleted = 0 AND (
            first_name LIKE '%' || :query || '%'
            OR last_name LIKE '%' || :query || '%'
            OR phone LIKE '%' || :query || '%'
            OR mobile LIKE '%' || :query || '%'
            OR email LIKE '%' || :query || '%'
            OR organization LIKE '%' || :query || '%'
        )
        ORDER BY first_name ASC, last_name ASC
        """
    )
    fun search(query: String): Flow<List<CustomerEntity>>

    /**
     * Bulk insert from server refresh. Uses IGNORE so locally-modified rows
     * (`locallyModified = true`) are NOT clobbered by the server's stale copy —
     * the sync layer is responsible for deciding when to `update()` them.
     */
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertAll(customers: List<CustomerEntity>)

    /**
     * Upsert a single customer (e.g. from a detail fetch). Prefer [upsert] over
     * an INSERT-OR-REPLACE because REPLACE triggers FK CASCADE, which would wipe
     * child rows. `@Upsert` performs INSERT-then-UPDATE without deleting the row.
     */
    @Upsert
    suspend fun upsert(customer: CustomerEntity)

    /** Legacy alias — prefer [upsert]. Kept for call sites that haven't migrated. */
    @Upsert
    suspend fun insert(customer: CustomerEntity)

    @Update
    suspend fun update(customer: CustomerEntity)

    @Query("DELETE FROM customers WHERE id = :id")
    suspend fun deleteById(id: Long)

    @Query("SELECT * FROM customers WHERE locally_modified = 1")
    suspend fun getLocallyModified(): List<CustomerEntity>

    @Query("SELECT COUNT(*) FROM customers WHERE is_deleted = 0")
    fun getCount(): Flow<Int>

    // ── §20.9 Cache eviction ─────────────────────────────────────────────────

    /** §20.9 — Total row count (including soft-deleted) for eviction math. */
    @Query("SELECT COUNT(*) FROM customers")
    suspend fun countAll(): Int

    /**
     * §20.9 — Evict the [excess] oldest customer rows that have no pending/syncing
     * sync_queue entry and are not locally modified. See [TicketDao.evictOldest]
     * for the full rationale on the LEFT JOIN guard.
     */
    @Query(
        """
        DELETE FROM customers
        WHERE id IN (
            SELECT c.id FROM customers c
            LEFT JOIN sync_queue sq
                ON sq.entity_type = 'customer'
               AND sq.entity_id   = c.id
               AND sq.status IN ('pending', 'syncing')
            WHERE sq.id IS NULL
              AND c.locally_modified = 0
            ORDER BY c.updated_at ASC
            LIMIT :excess
        )
        """,
    )
    suspend fun evictOldest(excess: Int)

}
