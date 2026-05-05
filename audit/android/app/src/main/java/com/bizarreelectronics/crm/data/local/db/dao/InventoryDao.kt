package com.bizarreelectronics.crm.data.local.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import androidx.room.Upsert
import com.bizarreelectronics.crm.data.local.db.entities.InventoryItemEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface InventoryDao {

    @Query("SELECT * FROM inventory_items ORDER BY name ASC")
    fun getAll(): Flow<List<InventoryItemEntity>>

    @Query("SELECT * FROM inventory_items WHERE id = :id")
    fun getById(id: Long): Flow<InventoryItemEntity?>

    @Query("SELECT * FROM inventory_items WHERE sku = :sku")
    fun getBySku(sku: String): Flow<InventoryItemEntity?>

    @Query(
        """
        SELECT * FROM inventory_items
        WHERE in_stock <= reorder_level AND reorder_level > 0
        ORDER BY name ASC
        """
    )
    fun getLowStock(): Flow<List<InventoryItemEntity>>

    @Query(
        """
        SELECT * FROM inventory_items
        WHERE name LIKE '%' || :query || '%'
            OR sku LIKE '%' || :query || '%'
            OR upc_code LIKE '%' || :query || '%'
        ORDER BY name ASC
        """
    )
    fun search(query: String): Flow<List<InventoryItemEntity>>

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertAll(items: List<InventoryItemEntity>)

    @Upsert
    suspend fun upsert(item: InventoryItemEntity)

    @Upsert
    suspend fun insert(item: InventoryItemEntity)

    @Update
    suspend fun update(item: InventoryItemEntity)

    @Query("UPDATE inventory_items SET in_stock = in_stock + :delta WHERE id = :id")
    suspend fun adjustStock(id: Long, delta: Int)

    @Query("DELETE FROM inventory_items WHERE id = :id")
    suspend fun deleteById(id: Long)

    @Query("SELECT * FROM inventory_items WHERE locally_modified = 1")
    suspend fun getLocallyModified(): List<InventoryItemEntity>

    // ── §20.9 Cache eviction ─────────────────────────────────────────────────

    /** §20.9 — Total row count for eviction math. */
    @Query("SELECT COUNT(*) FROM inventory_items")
    suspend fun countAll(): Int

    /**
     * §20.9 — Evict the [excess] oldest inventory rows with no pending/syncing
     * queue entry and not locally modified. See [TicketDao.evictOldest] for
     * the full rationale.
     */
    @Query(
        """
        DELETE FROM inventory_items
        WHERE id IN (
            SELECT i.id FROM inventory_items i
            LEFT JOIN sync_queue sq
                ON sq.entity_type = 'inventory'
               AND sq.entity_id   = i.id
               AND sq.status IN ('pending', 'syncing')
            WHERE sq.id IS NULL
              AND i.locally_modified = 0
            ORDER BY i.id ASC
            LIMIT :excess
        )
        """,
    )
    suspend fun evictOldest(excess: Int)
}
