package com.bizarreelectronics.crm.data.local.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import androidx.room.Upsert
import com.bizarreelectronics.crm.data.local.db.entities.TicketEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface TicketDao {

    @Query("SELECT * FROM tickets WHERE is_deleted = 0 ORDER BY created_at DESC")
    fun getAll(): Flow<List<TicketEntity>>

    @Query("SELECT * FROM tickets WHERE id = :id")
    fun getById(id: Long): Flow<TicketEntity?>

    @Query("SELECT * FROM tickets WHERE status_is_closed = 0 AND is_deleted = 0 ORDER BY created_at DESC")
    fun getOpenTickets(): Flow<List<TicketEntity>>

    @Query("SELECT * FROM tickets WHERE customer_id = :customerId AND is_deleted = 0 ORDER BY created_at DESC")
    fun getByCustomerId(customerId: Long): Flow<List<TicketEntity>>

    @Query(
        """
        SELECT * FROM tickets
        WHERE assigned_to = :userId AND status_is_closed = 0 AND is_deleted = 0
        ORDER BY created_at DESC
        """
    )
    fun getByAssignedTo(userId: Long): Flow<List<TicketEntity>>

    @Query(
        """
        SELECT * FROM tickets
        WHERE is_deleted = 0 AND (
            order_id LIKE '%' || :query || '%'
            OR status_name LIKE '%' || :query || '%'
            OR labels LIKE '%' || :query || '%'
        )
        ORDER BY created_at DESC
        """
    )
    fun search(query: String): Flow<List<TicketEntity>>

    @Query("SELECT * FROM tickets WHERE updated_at > :since")
    suspend fun getModifiedSince(since: String): List<TicketEntity>

    @Query("SELECT * FROM tickets WHERE locally_modified = 1")
    suspend fun getLocallyModified(): List<TicketEntity>

    /**
     * Bulk insert from server refresh. IGNORE conflicts so locally-modified rows
     * and child ticket_devices/ticket_notes are not wiped. Callers that want to
     * overwrite a specific ticket should call [upsert].
     */
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertAll(tickets: List<TicketEntity>)

    /** Upsert avoids REPLACE's delete-and-re-insert, which would cascade-delete
     * ticket_devices/ticket_notes. */
    @Upsert
    suspend fun upsert(ticket: TicketEntity)

    /** Legacy alias — routed through upsert to avoid CASCADE side effects. */
    @Upsert
    suspend fun insert(ticket: TicketEntity)

    @Update
    suspend fun update(ticket: TicketEntity)

    @Query("DELETE FROM tickets WHERE id = :id")
    suspend fun deleteById(id: Long)

    @Query("SELECT COUNT(*) FROM tickets WHERE is_deleted = 0")
    fun getCount(): Flow<Int>

    @Query("SELECT COUNT(*) FROM tickets WHERE status_is_closed = 0 AND is_deleted = 0")
    fun getOpenCount(): Flow<Int>
}
