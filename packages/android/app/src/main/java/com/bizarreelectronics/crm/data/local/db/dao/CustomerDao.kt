package com.bizarreelectronics.crm.data.local.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import androidx.room.Upsert
import com.bizarreelectronics.crm.data.local.db.entities.CustomerEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface CustomerDao {

    @Query("SELECT * FROM customers WHERE is_deleted = 0 ORDER BY first_name ASC, last_name ASC")
    fun getAll(): Flow<List<CustomerEntity>>

    @Query("SELECT * FROM customers WHERE id = :id")
    fun getById(id: Long): Flow<CustomerEntity?>

    @Query(
        """
        SELECT * FROM customers
        WHERE is_deleted = 0 AND (
            first_name LIKE '%' || :query || '%'
            OR last_name LIKE '%' || :query || '%'
            OR phone LIKE '%' || :query || '%'
            OR mobile LIKE '%' || :query || '%'
            OR email LIKE '%' || :query || '%'
            OR organization LIKE '%' || :query || '%'
        )
        ORDER BY first_name ASC, last_name ASC
        """
    )
    fun search(query: String): Flow<List<CustomerEntity>>

    /**
     * Bulk insert from server refresh. Uses IGNORE so locally-modified rows
     * (`locallyModified = true`) are NOT clobbered by the server's stale copy —
     * the sync layer is responsible for deciding when to `update()` them.
     */
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertAll(customers: List<CustomerEntity>)

    /**
     * Upsert a single customer (e.g. from a detail fetch). Prefer [upsert] over
     * an INSERT-OR-REPLACE because REPLACE triggers FK CASCADE, which would wipe
     * child rows. `@Upsert` performs INSERT-then-UPDATE without deleting the row.
     */
    @Upsert
    suspend fun upsert(customer: CustomerEntity)

    /** Legacy alias — prefer [upsert]. Kept for call sites that haven't migrated. */
    @Upsert
    suspend fun insert(customer: CustomerEntity)

    @Update
    suspend fun update(customer: CustomerEntity)

    @Query("DELETE FROM customers WHERE id = :id")
    suspend fun deleteById(id: Long)

    @Query("SELECT * FROM customers WHERE locally_modified = 1")
    suspend fun getLocallyModified(): List<CustomerEntity>

    @Query("SELECT COUNT(*) FROM customers WHERE is_deleted = 0")
    fun getCount(): Flow<Int>
}
