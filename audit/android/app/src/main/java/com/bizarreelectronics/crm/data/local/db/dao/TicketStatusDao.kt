package com.bizarreelectronics.crm.data.local.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Upsert
import com.bizarreelectronics.crm.data.local.db.entities.TicketStatusEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface TicketStatusDao {

    @Query("SELECT * FROM ticket_statuses ORDER BY sort_order ASC")
    fun getAll(): Flow<List<TicketStatusEntity>>

    /**
     * Bulk refresh of ticket statuses from the server. Uses IGNORE so we keep
     * any locally-cached statuses that the server didn't return. For a hard
     * refresh, call [upsert] on each row individually.
     */
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertAll(statuses: List<TicketStatusEntity>)

    @Upsert
    suspend fun upsert(status: TicketStatusEntity)
}
