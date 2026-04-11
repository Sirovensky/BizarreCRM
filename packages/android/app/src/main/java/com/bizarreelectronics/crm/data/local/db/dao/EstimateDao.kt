package com.bizarreelectronics.crm.data.local.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
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

    @Query("SELECT COUNT(*) FROM estimates WHERE is_deleted = 0")
    fun getCount(): Flow<Int>

    /**
     * @audit-fixed: Section 33 / D3 — `EstimateEntity.locallyModified` was a
     * write-only field. Without a way to enumerate dirty rows, the offline
     * estimate-edit flow could not be re-flushed after a SyncManager restart.
     */
    @Query("SELECT * FROM estimates WHERE locally_modified = 1")
    suspend fun getLocallyModified(): List<EstimateEntity>
}
