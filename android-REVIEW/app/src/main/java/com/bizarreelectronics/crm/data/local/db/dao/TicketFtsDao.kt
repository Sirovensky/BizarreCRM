package com.bizarreelectronics.crm.data.local.db.dao

import androidx.room.Dao
import androidx.room.Query
import com.bizarreelectronics.crm.data.local.db.entities.TicketEntity
import kotlinx.coroutines.flow.Flow

/**
 * FTS4-backed search queries for the `tickets_fts` virtual table.
 *
 * See [CustomerFtsDao] for full design rationale.
 *
 * ## IMEI search
 *
 * IMEI is stored on `ticket_devices`, not on `tickets`. A dedicated
 * [searchByImei] query uses a LIKE scan on `ticket_devices.imei` and joins
 * back to `tickets`. This is separate from FTS because IMEI is typically
 * entered as a long numeric string without word boundaries, which FTS4's
 * default tokenizer would split incorrectly.
 */
@Dao
interface TicketFtsDao {

    /**
     * Full-text prefix search on tickets (order ID, status, customer name,
     * device name, labels).
     *
     * [normalizedQuery] — FTS4-safe token string with optional trailing `*`
     * for prefix matching. E.g. `"ready*"` matches "Ready", "Ready for Pickup".
     */
    @Query(
        """
        SELECT t.*
        FROM tickets t
        INNER JOIN tickets_fts fts ON t.rowid = fts.rowid
        WHERE tickets_fts MATCH :normalizedQuery
          AND t.is_deleted = 0
        ORDER BY t.created_at DESC
        LIMIT 50
        """
    )
    fun searchFts(normalizedQuery: String): Flow<List<TicketEntity>>

    /**
     * IMEI / serial search — scans `ticket_devices` since IMEI lives there.
     *
     * Returns tickets that have at least one device whose IMEI or serial
     * contains [imeiFragment] as a substring. Case-insensitive LIKE.
     */
    @Query(
        """
        SELECT DISTINCT t.*
        FROM tickets t
        INNER JOIN ticket_devices td ON td.ticket_id = t.id
        WHERE (td.imei LIKE '%' || :imeiFragment || '%'
               OR td.serial LIKE '%' || :imeiFragment || '%')
          AND t.is_deleted = 0
        ORDER BY t.created_at DESC
        LIMIT 50
        """
    )
    fun searchByImei(imeiFragment: String): Flow<List<TicketEntity>>
}
