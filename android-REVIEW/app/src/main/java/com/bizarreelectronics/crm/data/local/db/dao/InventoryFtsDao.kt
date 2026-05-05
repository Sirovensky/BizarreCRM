package com.bizarreelectronics.crm.data.local.db.dao

import androidx.room.Dao
import androidx.room.Query
import com.bizarreelectronics.crm.data.local.db.entities.InventoryItemEntity
import kotlinx.coroutines.flow.Flow

/**
 * FTS4-backed search queries for the `inventory_fts` virtual table.
 *
 * See [CustomerFtsDao] for full design rationale.
 *
 * Indexed fields: name, SKU, UPC, category, manufacturer name, supplier name,
 * description. SKU and UPC are also covered by the LIKE-based fallback in
 * [InventoryDao.search] for exact-match scenarios where FTS tokenization would
 * split the code incorrectly.
 */
@Dao
interface InventoryFtsDao {

    /**
     * Full-text prefix search on inventory items.
     *
     * [normalizedQuery] — FTS4-safe token string with optional trailing `*`.
     * E.g. `"screen*"` matches "Screen", "Screen Assembly", "Screen Digitizer".
     */
    @Query(
        """
        SELECT i.*
        FROM inventory_items i
        INNER JOIN inventory_fts fts ON i.rowid = fts.rowid
        WHERE inventory_fts MATCH :normalizedQuery
        ORDER BY i.name ASC
        LIMIT 50
        """
    )
    fun searchFts(normalizedQuery: String): Flow<List<InventoryItemEntity>>
}
