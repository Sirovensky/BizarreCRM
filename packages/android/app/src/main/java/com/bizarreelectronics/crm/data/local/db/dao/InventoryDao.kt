package com.bizarreelectronics.crm.data.local.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
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

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(items: List<InventoryItemEntity>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(item: InventoryItemEntity)

    @Update
    suspend fun update(item: InventoryItemEntity)

    @Query("UPDATE inventory_items SET in_stock = in_stock + :delta WHERE id = :id")
    suspend fun adjustStock(id: Long, delta: Int)

    @Query("DELETE FROM inventory_items WHERE id = :id")
    suspend fun deleteById(id: Long)

    @Query("SELECT * FROM inventory_items WHERE locally_modified = 1")
    suspend fun getLocallyModified(): List<InventoryItemEntity>
}
