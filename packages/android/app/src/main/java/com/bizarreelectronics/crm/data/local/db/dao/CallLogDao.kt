package com.bizarreelectronics.crm.data.local.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.bizarreelectronics.crm.data.local.db.entities.CallLogEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface CallLogDao {

    @Query("SELECT * FROM call_logs ORDER BY created_at DESC")
    fun getAll(): Flow<List<CallLogEntity>>

    @Query("SELECT * FROM call_logs WHERE conv_phone = :phone ORDER BY created_at DESC")
    fun getByConvPhone(phone: String): Flow<List<CallLogEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(log: CallLogEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(logs: List<CallLogEntity>)
}
