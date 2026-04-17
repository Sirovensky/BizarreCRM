package com.bizarreelectronics.crm.data.local.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Update
import androidx.room.Upsert
import com.bizarreelectronics.crm.data.local.db.entities.LeadEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface LeadDao {

    @Query("SELECT * FROM leads WHERE is_deleted = 0 ORDER BY created_at DESC")
    fun getAll(): Flow<List<LeadEntity>>

    @Query("SELECT * FROM leads WHERE id = :id")
    fun getById(id: Long): Flow<LeadEntity?>

    @Query("SELECT * FROM leads WHERE status = :status AND is_deleted = 0 ORDER BY created_at DESC")
    fun getByStatus(status: String): Flow<List<LeadEntity>>

    @Query(
        """
        SELECT * FROM leads
        WHERE is_deleted = 0 AND (
            first_name LIKE '%' || :query || '%'
            OR last_name LIKE '%' || :query || '%'
            OR phone LIKE '%' || :query || '%'
            OR email LIKE '%' || :query || '%'
            OR order_id LIKE '%' || :query || '%'
        )
        ORDER BY created_at DESC
        """
    )
    fun search(query: String): Flow<List<LeadEntity>>

    @Query(
        """
        SELECT * FROM leads
        WHERE status NOT IN ('converted', 'lost') AND is_deleted = 0
        ORDER BY created_at DESC
        """
    )
    fun getOpenLeads(): Flow<List<LeadEntity>>

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertAll(leads: List<LeadEntity>)

    @Upsert
    suspend fun upsert(lead: LeadEntity)

    @Upsert
    suspend fun insert(lead: LeadEntity)

    @Update
    suspend fun update(lead: LeadEntity)

    @Query("DELETE FROM leads WHERE id = :id")
    suspend fun deleteById(id: Long)

    /**
     * Atomically swap a temp (negative-id) lead row for the server-authoritative row.
     * Upsert-first, delete-last inside a single Room transaction so concurrent readers
     * never observe a window with zero rows. Idempotent: a no-op when the server
     * echoes the temp id back or when the temp row is already gone. See
     * AND-20260414-H6.
     */
    @Transaction
    suspend fun reconcileTempId(tempId: Long, newEntity: LeadEntity) {
        if (newEntity.id == tempId) {
            upsert(newEntity)
            return
        }
        upsert(newEntity)
        deleteById(tempId)
    }

    @Query("SELECT * FROM leads WHERE locally_modified = 1")
    suspend fun getLocallyModified(): List<LeadEntity>

    /**
     * @audit-fixed: AND-20260414-H5 — rewrite leads that reference a temp customer
     * id to the server-assigned real customer id. Called from SyncManager after a
     * customer sync succeeds and before the temp customer row is removed.
     * Idempotent: a no-op when no rows match.
     */
    @Query("UPDATE leads SET customer_id = :newRealId WHERE customer_id = :oldTempId")
    suspend fun updateCustomerIdByOldTempId(oldTempId: Long, newRealId: Long)

    @Query("SELECT COUNT(*) FROM leads WHERE is_deleted = 0")
    fun getCount(): Flow<Int>
}
