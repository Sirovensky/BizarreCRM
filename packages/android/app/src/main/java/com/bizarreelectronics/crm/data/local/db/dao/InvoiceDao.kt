package com.bizarreelectronics.crm.data.local.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.bizarreelectronics.crm.data.local.db.entities.InvoiceEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface InvoiceDao {

    @Query("SELECT * FROM invoices ORDER BY created_at DESC")
    fun getAll(): Flow<List<InvoiceEntity>>

    @Query("SELECT * FROM invoices WHERE id = :id")
    fun getById(id: Long): Flow<InvoiceEntity?>

    @Query("SELECT * FROM invoices WHERE customer_id = :customerId ORDER BY created_at DESC")
    fun getByCustomerId(customerId: Long): Flow<List<InvoiceEntity>>

    @Query("SELECT * FROM invoices WHERE status = :status ORDER BY created_at DESC")
    fun getByStatus(status: String): Flow<List<InvoiceEntity>>

    @Query("SELECT SUM(amount_due) FROM invoices WHERE amount_due > 0")
    fun getOutstandingBalance(): Flow<Double?>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(invoices: List<InvoiceEntity>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(invoice: InvoiceEntity)

    @Update
    suspend fun update(invoice: InvoiceEntity)
}
