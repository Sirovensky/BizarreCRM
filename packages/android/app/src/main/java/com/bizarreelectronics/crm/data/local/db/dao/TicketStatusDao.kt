package com.bizarreelectronics.crm.data.local.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.bizarreelectronics.crm.data.local.db.entities.TicketStatusEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface TicketStatusDao {

    @Query("SELECT * FROM ticket_statuses ORDER BY sort_order ASC")
    fun getAll(): Flow<List<TicketStatusEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(statuses: List<TicketStatusEntity>)
}
