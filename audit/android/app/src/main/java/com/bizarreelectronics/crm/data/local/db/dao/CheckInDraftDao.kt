package com.bizarreelectronics.crm.data.local.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.bizarreelectronics.crm.data.local.db.entities.CheckInDraftEntity

@Dao
interface CheckInDraftDao {

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: CheckInDraftEntity)

    @Query("SELECT * FROM checkin_drafts WHERE customer_id = :customerId AND device_id = :deviceId LIMIT 1")
    suspend fun get(customerId: Long, deviceId: Long): CheckInDraftEntity?

    @Query("DELETE FROM checkin_drafts WHERE customer_id = :customerId AND device_id = :deviceId")
    suspend fun delete(customerId: Long, deviceId: Long)

    /** Prune drafts older than [cutoffMs] to avoid stale check-in sessions accumulating. */
    @Query("DELETE FROM checkin_drafts WHERE updated_at < :cutoffMs")
    suspend fun deleteOlderThan(cutoffMs: Long): Int
}
