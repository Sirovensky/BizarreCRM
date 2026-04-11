package com.bizarreelectronics.crm.data.local.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
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

    @Query("SELECT * FROM leads WHERE locally_modified = 1")
    suspend fun getLocallyModified(): List<LeadEntity>

    @Query("SELECT COUNT(*) FROM leads WHERE is_deleted = 0")
    fun getCount(): Flow<Int>
}
