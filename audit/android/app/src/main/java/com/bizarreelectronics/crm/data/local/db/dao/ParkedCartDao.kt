package com.bizarreelectronics.crm.data.local.db.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.bizarreelectronics.crm.data.local.db.entities.ParkedCartEntity
import kotlinx.coroutines.flow.Flow

/**
 * DAO for parked POS carts.
 *
 * Plan §16.1 L1800 — offline parked cart persistence.
 */
@Dao
interface ParkedCartDao {

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(cart: ParkedCartEntity)

    @Delete
    suspend fun delete(cart: ParkedCartEntity)

    @Query("DELETE FROM parked_carts WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("SELECT * FROM parked_carts ORDER BY parked_at DESC")
    fun observeAll(): Flow<List<ParkedCartEntity>>

    @Query("SELECT COUNT(*) FROM parked_carts")
    fun observeCount(): Flow<Int>

    @Query("SELECT * FROM parked_carts WHERE id = :id")
    suspend fun getById(id: String): ParkedCartEntity?
}
