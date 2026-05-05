package com.bizarreelectronics.crm.data.local.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import androidx.room.Upsert
import com.bizarreelectronics.crm.data.local.db.entities.SmsMessageEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface SmsDao {

    @Query(
        """
        SELECT * FROM sms_messages
        WHERE id IN (SELECT MAX(id) FROM sms_messages GROUP BY conv_phone)
        ORDER BY created_at DESC
        """
    )
    fun getConversations(): Flow<List<SmsMessageEntity>>

    @Query("SELECT * FROM sms_messages WHERE conv_phone = :phone ORDER BY created_at ASC")
    fun getByConvPhone(phone: String): Flow<List<SmsMessageEntity>>

    @Upsert
    suspend fun upsert(message: SmsMessageEntity)

    @Upsert
    suspend fun insert(message: SmsMessageEntity)

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertAll(messages: List<SmsMessageEntity>)

    @Update
    suspend fun update(message: SmsMessageEntity)

    @Query("UPDATE sms_messages SET status = :status WHERE id = :id")
    suspend fun updateStatus(id: Long, status: String)
}
