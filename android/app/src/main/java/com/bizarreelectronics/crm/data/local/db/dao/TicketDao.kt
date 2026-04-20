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

    /**
     * @audit-fixed: Section 33 / D7 — re-point child `ticket_devices` rows from a
     * temp ticket id to the real server-assigned id. Used by SyncManager's temp-id
     * reconciliation path so that the subsequent `deleteById(tempId)` no longer
     * fires the CASCADE rule on children that the user added while offline.
     */
    @Query("UPDATE ticket_devices SET ticket_id = :serverId WHERE ticket_id = :tempId")
    suspend fun repointDevices(tempId: Long, serverId: Long)

    /**
     * @audit-fixed: Section 33 / D7 — companion to [repointDevices] for ticket
     * notes captured offline. See class docstring for the full lifecycle.
     */
    @Query("UPDATE ticket_notes SET ticket_id = :serverId WHERE ticket_id = :tempId")
    suspend fun repointNotes(tempId: Long, serverId: Long)

    /**
     * @audit-fixed: AND-20260414-H5 — rewrite every ticket row that points at a
     * now-obsolete temp customer id so it points at the server-assigned real id
     * instead. Called from SyncManager after a customer sync succeeds and before
     * the temp customer row is removed. Idempotent: if no rows carry [oldTempId],
     * the UPDATE is a no-op, so retried syncs never double-rewrite.
     */
    @Query("UPDATE tickets SET customer_id = :newRealId WHERE customer_id = :oldTempId")
    suspend fun updateCustomerIdByOldTempId(oldTempId: Long, newRealId: Long)

    @Query("SELECT COUNT(*) FROM tickets WHERE is_deleted = 0")
    fun getCount(): Flow<Int>

    @Query("SELECT COUNT(*) FROM tickets WHERE status_is_closed = 0 AND is_deleted = 0")
    fun getOpenCount(): Flow<Int>
}
