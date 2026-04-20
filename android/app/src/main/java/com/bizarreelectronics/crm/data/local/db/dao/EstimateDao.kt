package com.bizarreelectronics.crm.data.local.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Update
import androidx.room.Upsert
import com.bizarreelectronics.crm.data.local.db.entities.EstimateEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface EstimateDao {

    @Query("SELECT * FROM estimates WHERE is_deleted = 0 ORDER BY created_at DESC")
    fun getAll(): Flow<List<EstimateEntity>>

    @Query("SELECT * FROM estimates WHERE id = :id")
    fun getById(id: Long): Flow<EstimateEntity?>

    @Query("SELECT * FROM estimates WHERE status = :status AND is_deleted = 0 ORDER BY created_at DESC")
    fun getByStatus(status: String): Flow<List<EstimateEntity>>

    @Query(
        """
        SELECT * FROM estimates
        WHERE is_deleted = 0 AND (
            order_id LIKE '%' || :query || '%'
            OR customer_name LIKE '%' || :query || '%'
            OR notes LIKE '%' || :query || '%'
        )
        ORDER BY created_at DESC
        """
    )
    fun search(query: String): Flow<List<EstimateEntity>>

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertAll(estimates: List<EstimateEntity>)

    @Upsert
    suspend fun upsert(estimate: EstimateEntity)

    @Upsert
    suspend fun insert(estimate: EstimateEntity)

    @Update
    suspend fun update(estimate: EstimateEntity)

    @Query("DELETE FROM estimates WHERE id = :id")
    suspend fun deleteById(id: Long)

    /**
     * Atomically swap a temp (negative-id) estimate row for the server-authoritative
     * row. Upsert-first, delete-last inside a single Room transaction so concurrent
     * readers never observe a window with zero rows. Idempotent: a no-op when the
     * server echoes the temp id back or when the temp row is already gone. See
     * AND-20260414-H6.
     */
    @Transaction
    suspend fun reconcileTempId(tempId: Long, newEntity: EstimateEntity) {
        if (newEntity.id == tempId) {
            upsert(newEntity)
            return
        }
        upsert(newEntity)
        deleteById(tempId)
    }

    @Query("SELECT COUNT(*) FROM estimates WHERE is_deleted = 0")
    fun getCount(): Flow<Int>

    /**
     * @audit-fixed: Section 33 / D3 — `EstimateEntity.locallyModified` was a
     * write-only field. Without a way to enumerate dirty rows, the offline
     * estimate-edit flow could not be re-flushed after a SyncManager restart.
     */
    @Query("SELECT * FROM estimates WHERE locally_modified = 1")
    suspend fun getLocallyModified(): List<EstimateEntity>

    /**
     * @audit-fixed: AND-20260414-H5 — rewrite estimates that reference a temp
     * customer id to the server-assigned real customer id. Called from SyncManager
     * after a customer sync succeeds and before the temp customer row is removed.
     * Idempotent: a no-op when no rows match.
     */
    @Query("UPDATE estimates SET customer_id = :newRealId WHERE customer_id = :oldTempId")
    suspend fun updateCustomerIdByOldTempId(oldTempId: Long, newRealId: Long)
}
